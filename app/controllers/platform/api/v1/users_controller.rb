class Platform::Api::V1::UsersController < PlatformController
  # ref: https://stackoverflow.com/a/45190318/939299
  # set resource is called for other actions already in platform controller
  # we want to add login and token to that chain as well
  before_action(only: [:login, :token]) { set_resource }
  before_action(only: [:login, :token]) { validate_platform_app_permissible }

  def show; end

  def create
    @resource = (User.from_email(user_params[:email]) || User.new(user_params))
    @resource.skip_confirmation!
    @resource.save!
    @platform_app.platform_app_permissibles.find_or_create_by!(permissible: @resource)
  end

  # GET /platform/api/v1/users/:id/login[?account_id=N]
  #
  # account_id IS OPTIONAL AND IS VERIFIED, NOT TRUSTED. Without it the link behaves exactly as it always
  # has -- an unscoped session for that user, which is what every existing caller gets and what independent
  # sign-in needs. With it, the resulting session may act on that account and no other.
  #
  # Two checks before the scope is honoured, because a scope the caller could choose freely would be
  # decoration: the app must already hold a permissible on that account (so it cannot scope a link into a
  # workspace it was never granted), and the user must be a member of it (so it cannot mint a session for
  # an account the person does not belong to). Failing either is a refusal rather than a silent downgrade to
  # unscoped -- a caller that asked for a boundary and was quietly given none is worse off than one that was
  # told no.
  def login
    account_id = params[:account_id].presence
    return render json: { url: @resource.generate_sso_link } if account_id.nil?

    account = Account.find_by(id: account_id)

    unless account && @platform_app.platform_app_permissibles.exists?(permissible: account) &&
           account.account_users.exists?(user_id: @resource.id)
      return render json: { error: 'Not permissible for that account' }, status: :unauthorized
    end

    render json: { url: @resource.generate_sso_link(account_id: account.id) }
  end

  def token; end

  def update
    @resource.assign_attributes(user_update_params)

    # We are using devise's reconfirmable flow for changing emails
    # But in case of platform APIs we don't want user to go through this extra step
    @resource.skip_reconfirmation! if user_update_params[:email].present?
    @resource.save!
  end

  def destroy
    DeleteObjectJob.perform_later(@resource)
    head :ok
  end

  private

  def user_custom_attributes
    return @resource.custom_attributes.merge(user_params[:custom_attributes]) if user_params[:custom_attributes]

    @resource.custom_attributes
  end

  def user_update_params
    # we want the merged custom attributes not the original one
    user_params.except(:custom_attributes).merge({ custom_attributes: user_custom_attributes })
  end

  def set_resource
    @resource = User.find(params[:id])
  end

  def user_params
    params.permit(:name, :display_name, :email, :password, custom_attributes: {})
  end
end
