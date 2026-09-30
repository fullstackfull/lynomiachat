# GET /commerce/shopify/callback, the redirect URL of the Lynomia Commerce Shopify app
# (docs/commerce/18-shopify-oauth-and-tokens.md). The legacy Shopify integration keeps its own /shopify/callback.
#
# Before the code is used, three checks, in this order: Shopify signed this query (Commerce::Shopify::Oauth HMAC with a
# fresh timestamp), the state is valid (Commerce::OauthState: signature, expiry, one use, the browser that started it),
# and the shop Shopify signed is the shop the administrator started with. The account and administrator come only from
# the state and are checked again: the user is still an administrator of the account, and the account and installation
# still offer Shopify Commerce. The browser returns to Settings → Commerce with `shopify=connected` or
# `shopify_error=<code>`; a callback that fails the three checks changes nothing and names no account.
class Commerce::Shopify::CallbacksController < ApplicationController
  COOKIE = :lynomia_shopify_oauth

  # A request Shopify did not sign touches nothing, not even the browser's state cookie.
  def show
    return redirect_to(app_url, allow_other_host: true) unless Commerce::Shopify::Oauth.valid_callback?(request.query_parameters)

    grant = Commerce::OauthState.consume('shopify', params[:state], cookies.encrypted[COOKIE])
    cookies.delete(COOKIE, path: Commerce::Shopify::Config::CALLBACK_PATH)
    return redirect_to(app_url, allow_other_host: true) unless grant && grant['shop'] == params[:shop]

    @account = Account.find(grant['account_id'])
    redirect_to return_url(connect(grant)), allow_other_host: true
  end

  private

  def app_url = "#{ENV.fetch('FRONTEND_URL')}/app"

  def connect(grant)
    user = User.find_by(id: grant['user_id'])
    raise Commerce::Error, 'PERMISSION_DENIED' unless user && administrator?(user) && @account.feature_enabled?('lynomia_commerce')
    raise Commerce::Error, 'PROVIDER_DISABLED' unless Commerce::Providers.enabled?('shopify')
    raise Commerce::Error.new('AUTH_INVALID', reason: 'shopify_authorization_denied') if params[:code].blank?

    Commerce::Shopify::Authorization.new(account: @account, user: user).connect(grant['shop'], params[:code].to_s)
    { shopify: 'connected' }
  rescue Commerce::Error => e
    { shopify_error: e.code }
  end

  def administrator?(user)
    account_user = @account.account_users.find_by(user: user)
    account_user.present? && Commerce::StorePolicy.new({ user: user, account: @account, account_user: account_user }, Commerce::Store).create?
  end

  def return_url(result)
    "#{ENV.fetch('FRONTEND_URL')}/app/accounts/#{@account.id}/settings/commerce?#{result.to_query}"
  end
end
