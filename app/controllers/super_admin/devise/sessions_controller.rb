# frozen_string_literal: true

class SuperAdmin::Devise::SessionsController < Devise::SessionsController
  MFA_ERROR = 'Invalid authentication code. Please try again.'

  def new
    self.resource = resource_class.new(sign_in_params)
  end

  def create
    redirect_to(super_admin_session_path, flash: { error: @error_message }) && return unless valid_credentials?
    redirect_to(super_admin_session_path, flash: { error: MFA_ERROR }) && return unless second_factor_satisfied?

    sign_in(:super_admin, @super_admin)
    flash.discard
    redirect_to super_admin_root_path
  end

  def destroy
    sign_out
    flash.discard
    redirect_to '/'
  end

  private

  def valid_credentials?
    @super_admin = SuperAdmin.find_by!(email: params[:super_admin][:email])
    raise StandardError, 'Invalid Password' unless @super_admin.valid_password?(params[:super_admin][:password])

    true
  rescue StandardError => e
    Rails.logger.error e.message
    @error_message = 'Invalid credentials. Please try again.'
    false
  end

  # A super admin reaches every account's data, so a password alone must not be enough once they have turned on
  # two-factor authentication. Same service the agent sign-in uses, so there is one MFA implementation; rack_attack
  # already throttles this path by IP and by email, which is what keeps the code from being guessable.
  def second_factor_satisfied?
    return true unless @super_admin.otp_required_for_login

    code = params[:super_admin][:otp_code].to_s.strip
    return false if code.blank?

    # One field, either kind of code: the service takes the two separately and tries only the one it is given, so a
    # failed authenticator code falls through to a backup code. Neither attempt has a side effect when it fails.
    authenticate_code(otp_code: code) || authenticate_code(backup_code: code)
  end

  def authenticate_code(**code)
    Mfa::AuthenticationService.new(user: @super_admin, **code).authenticate
  end
end
