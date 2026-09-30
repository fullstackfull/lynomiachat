# GET /commerce/zid/callback, the callback URL of the Lynomia Zid app (docs/commerce/14-zid-oauth-and-tokens.md).
#
# The state is checked first (Commerce::OauthState: signature, expiry, one use, the browser that started it). The
# account and administrator come only from it and are checked again: the user is still an administrator of the account,
# and the account and installation still offer Zid. Only then is the code read and exchanged server-side. The browser
# returns to Settings → Commerce with `zid=connected` or `zid_error=<code>`; a callback without a valid state changes
# nothing and names no account.
class Commerce::Zid::CallbacksController < ApplicationController
  COOKIE = :lynomia_zid_oauth

  def show
    grant = Commerce::OauthState.consume('zid', params[:state], cookies.encrypted[COOKIE])
    cookies.delete(COOKIE, path: Commerce::Zid::Config::CALLBACK_PATH)
    return redirect_to("#{ENV.fetch('FRONTEND_URL')}/app", allow_other_host: true) unless grant

    @account = Account.find(grant['account_id'])
    redirect_to return_url(connect(User.find_by(id: grant['user_id']))), allow_other_host: true
  end

  private

  def connect(user)
    raise Commerce::Error, 'PERMISSION_DENIED' unless user && administrator?(user) && @account.feature_enabled?('lynomia_commerce')
    raise Commerce::Error, 'PROVIDER_DISABLED' unless Commerce::Providers.enabled?('zid')
    raise Commerce::Error.new('AUTH_INVALID', reason: 'zid_authorization_denied') if params[:code].blank?

    Commerce::Zid::Authorization.new(account: @account, user: user).connect(params[:code].to_s)
    { zid: 'connected' }
  rescue Commerce::Error => e
    { zid_error: e.code }
  end

  def administrator?(user)
    account_user = @account.account_users.find_by(user: user)
    account_user.present? && Commerce::StorePolicy.new({ user: user, account: @account, account_user: account_user }, Commerce::Store).create?
  end

  def return_url(result)
    "#{ENV.fetch('FRONTEND_URL')}/app/accounts/#{@account.id}/settings/commerce?#{result.to_query}"
  end
end
