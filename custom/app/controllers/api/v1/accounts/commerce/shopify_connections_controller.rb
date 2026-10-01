# Connecting a Shopify shop through the Lynomia Commerce Shopify app (administrators, `lynomia_commerce` accounts,
# installations that offer Shopify Commerce).
#
#   POST /api/v1/accounts/:account_id/commerce/shopify_connection   { shop[, order_actions: true] } → { authorize_url } for
#        "Connect with Shopify", or for "Reconnect Shopify to enable order actions" (write_orders is asked only then, and
#        only while the installation offers Shopify order actions)
#
# `shop` is the shop's myshopify.com domain, validated by Shopify::ShopDomain: no other host, no scheme, port, path,
# userinfo, query or fragment. A shop this account already shows through the legacy Shopify integration is refused, so
# its orders never appear twice; the legacy integration itself is left as it is. The browser is sent to the shop to
# authorize the app and comes back to Commerce::Shopify::CallbacksController with a code and the signed state issued
# here, which carries the shop. The state's nonce is also set in an encrypted HttpOnly cookie, so only this browser can
# complete the authorization. No token ever passes through the browser.
class Api::V1::Accounts::Commerce::ShopifyConnectionsController < Api::V1::Accounts::BaseController
  before_action :ensure_commerce_enabled
  before_action -> { authorize(::Commerce::Store, :create?) }
  before_action :ensure_shopify_enabled

  rescue_from ::Commerce::Error do |error|
    render json: { error: error.as_json }, status: :unprocessable_entity
  end

  def create
    raise ::Commerce::Error, 'ENCRYPTION_NOT_CONFIGURED' unless Chatwoot.encryption_configured?

    shop = ::Shopify::ShopDomain.normalize(params[:shop])
    raise ::Commerce::Error.new('INVALID_STORE_URL', reason: 'shopify_domain') unless ::Shopify::ShopDomain.valid?(shop)
    raise ::Commerce::Error.new('STORE_ALREADY_CONNECTED', reason: 'legacy_shopify_integration') if legacy_integration?(shop)

    scopes = requested_scopes
    issued = ::Commerce::OauthState.issue('shopify', account: Current.account, user: Current.user, shop: shop, scopes: scopes.join(','))
    remember_browser(issued.nonce)
    render json: { authorize_url: ::Commerce::Shopify::Oauth.authorize_url(shop, issued.state, scopes) }, status: :created
  end

  private

  def ensure_commerce_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('lynomia_commerce')
  end

  def ensure_shopify_enabled
    raise ::Commerce::Error, 'PROVIDER_DISABLED' unless ::Commerce::Providers.enabled?('shopify')
  end

  def remember_browser(nonce)
    cookies.encrypted[::Commerce::Shopify::CallbacksController::COOKIE] = {
      value: nonce, expires: ::Commerce::OauthState::TTL.from_now, httponly: true, same_site: :lax, secure: request.ssl?,
      path: ::Commerce::Shopify::Config::CALLBACK_PATH
    }
  end

  # write_orders only for an administrator's reconnect for order actions, while the installation offers them.
  def requested_scopes
    return ::Commerce::Shopify::Config::SCOPES unless params[:order_actions] == true
    unless ::Commerce::Switches.provider_actions_enabled?('shopify')
      raise ::Commerce::Error.new('ACTIONS_DISABLED', reason: 'provider_actions_disabled')
    end

    ::Commerce::Shopify::Config::ACTION_SCOPES
  end

  def legacy_integration?(shop)
    Current.account.hooks.exists?(app_id: 'shopify', reference_id: shop)
  end
end
