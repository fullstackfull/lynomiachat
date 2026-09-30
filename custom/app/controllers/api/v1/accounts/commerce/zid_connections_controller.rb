# Connecting a Zid store (administrators, `lynomia_commerce` accounts, installations that offer Zid).
#
#   POST /api/v1/accounts/:account_id/commerce/zid_connection   { authorize_url } for "Connect with Zid"
#
# The browser is sent to Zid to authorize the Lynomia app and comes back to Commerce::Zid::CallbacksController with a
# code and the signed state issued here. The state's nonce is also set in an encrypted HttpOnly cookie, so only this
# browser can complete the authorization. No token ever passes through the browser.
class Api::V1::Accounts::Commerce::ZidConnectionsController < Api::V1::Accounts::BaseController
  before_action :ensure_commerce_enabled
  before_action -> { authorize(::Commerce::Store, :create?) }
  before_action :ensure_zid_enabled

  rescue_from ::Commerce::Error do |error|
    render json: { error: error.as_json }, status: :unprocessable_entity
  end

  def create
    raise ::Commerce::Error, 'ENCRYPTION_NOT_CONFIGURED' unless Chatwoot.encryption_configured?

    issued = ::Commerce::Zid::OauthState.issue(account: Current.account, user: Current.user)
    cookies.encrypted[::Commerce::Zid::CallbacksController::COOKIE] = {
      value: issued.nonce, expires: ::Commerce::Zid::OauthState::TTL.from_now, httponly: true, same_site: :lax, secure: request.ssl?,
      path: ::Commerce::Zid::Config::CALLBACK_PATH
    }
    render json: { authorize_url: ::Commerce::Zid::Oauth.authorize_url(issued.state) }, status: :created
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  def ensure_zid_enabled
    raise ::Commerce::Error, 'PROVIDER_DISABLED' unless ::Commerce::Providers.enabled?('zid')
  end
end
