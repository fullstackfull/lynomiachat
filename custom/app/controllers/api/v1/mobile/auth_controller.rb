# frozen_string_literal: true

# Mobile sign-in with Google / Apple.
#
#   POST /api/v1/mobile/auth/google  { id_token }
#   POST /api/v1/mobile/auth/apple   { identity_token, name (optional, Apple sends it only on first sign-in) }
#
# Returns, like /auth/sign_in:
#   - data.access_token : the user's API token -> send it as header `api_access_token`
#   - data.pubsub_token : for the realtime (websocket) connection
#   - auth / headers    : session credentials (access-token, client, uid), optional alternative
class Api::V1::Mobile::AuthController < ActionController::API
  MFA_MESSAGE = 'This user has two-factor authentication enabled. Sign in with email and password.'

  def google
    sign_in_with('google', params[:id_token])
  end

  def apple
    sign_in_with('apple', params[:identity_token], name: params[:name])
  end

  private

  def sign_in_with(provider, token, name: nil)
    claims = MobileAuth::TokenVerifier.new(provider).verify(token)
    result = MobileAuth::SignIn.new(provider: provider, claims: claims, name: name).perform
    return render_error('mfa_required', MFA_MESSAGE, :forbidden) if mfa_enabled?(result.user)

    render_signed_in(result)
  rescue MobileAuth::TokenVerifier::InvalidToken => e
    render_error('invalid_token', e.message, :unauthorized)
  rescue MobileAuth::TokenVerifier::NotConfigured => e
    render_error('not_configured', e.message, :service_unavailable)
  rescue MobileAuth::SignIn::Error => e
    render_error(e.code, e.message, :unprocessable_entity)
  rescue ActiveRecord::RecordInvalid => e
    render_error('invalid_record', e.record.errors.full_messages.to_sentence, :unprocessable_entity)
  end

  def render_signed_in(result)
    user = result.user
    auth = user.create_new_auth_token
    response.headers.merge!(auth)
    render json: { data: user_data(user, result.new_user), auth: auth }
  end

  def user_data(user, new_user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      access_token: user.access_token&.token,
      pubsub_token: user.pubsub_token,
      new_user: new_user,
      accounts: user.account_users.includes(:account).map do |account_user|
        { id: account_user.account_id, name: account_user.account.name, role: account_user.role }
      end
    }
  end

  def mfa_enabled?(user)
    user.respond_to?(:otp_required_for_login) && user.otp_required_for_login
  end

  def render_error(code, message, status)
    render json: { error: code, message: message }, status: status
  end
end
