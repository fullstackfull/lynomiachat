class Api::V1::ProfilesController < Api::BaseController
  # for sso_account_scope -- these actions name their own account instead of going through the chokepoint
  include EnsureCurrentAccountHelper
  before_action :set_user
  # The profile surface renders the same account list partial as sign-in does.
  before_action -> { @sso_account_scope = sso_account_scope }

  def show; end

  def update
    if password_params[:password].present?
      render_could_not_create_error('Invalid current password') and return unless @user.valid_password?(password_params[:current_password])

      @user.update!(password_params.except(:current_password))
    end

    @user.assign_attributes(profile_params)
    @user.custom_attributes.merge!(custom_attributes_params)
    @user.save!
  end

  def avatar
    @user.avatar.attachment.destroy! if @user.avatar.attached?
    @user.reload
  end

  # THESE THREE TAKE AN ACCOUNT ID FROM THE BODY, so a session restricted to one workspace could otherwise
  # reach into another through the profile surface -- flipping a colleague's availability, or moving the
  # account the dashboard restores into. Writes, not reads, which is why they are guarded rather than merely
  # filtered.
  def auto_offline
    return unless scoped_membership_permits?(auto_offline_params[:account_id])

    @user.account_users.find_by!(account_id: auto_offline_params[:account_id]).update!(auto_offline: auto_offline_params[:auto_offline] || false)
  end

  def availability
    return unless scoped_membership_permits?(availability_params[:account_id])

    @user.account_users.find_by!(account_id: availability_params[:account_id]).update!(availability: availability_params[:availability])
  end

  def set_active_account
    return unless scoped_membership_permits?(profile_params[:account_id])

    @user.account_users.find_by(account_id: profile_params[:account_id]).update(active_at: Time.now.utc)
    head :ok
  end

  def resend_confirmation
    @user.send_confirmation_instructions unless @user.confirmed?
    head :ok
  end

  def reset_access_token
    @user.access_token.regenerate_token
    @user.reload
  end

  private

  # Renders and returns false when the session may not touch that account. An unscoped session -- every
  # ordinary login -- permits everything, exactly as before.
  def scoped_membership_permits?(account_id)
    scope = sso_account_scope
    return true if scope.blank? || account_id.blank? || scope.to_i == account_id.to_i

    render_unauthorized(I18n.t('errors.account.not_authorized'))
    false
  end

  def set_user
    @user = current_user
  end

  def availability_params
    params.require(:profile).permit(:account_id, :availability)
  end

  def auto_offline_params
    params.require(:profile).permit(:account_id, :auto_offline)
  end

  def profile_params
    params.require(:profile).permit(
      :email,
      :name,
      :display_name,
      :avatar,
      :message_signature,
      :account_id,
      ui_settings: {}
    )
  end

  def custom_attributes_params
    params.require(:profile).permit(:phone_number)
  end

  def password_params
    params.require(:profile).permit(
      :current_password,
      :password,
      :password_confirmation
    )
  end
end
