# Connects the Shopify shop behind an authorization code to the account and administrator named by the OAuth state
# (docs/commerce/18-shopify-oauth-and-tokens.md). The code is exchanged server-side for an expiring offline token, the
# granted scopes are checked, and the shop is confirmed through the Admin API; only then is anything saved: a new store
# through Commerce::StoreConnection's ownership rules (a shop connected to another account is never moved), or the new
# token for this account's own store (re-authorization).
class Commerce::Shopify::Authorization
  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def connect(shop, code)
    status, body = Commerce::Shopify::Oauth.token(shop, code: code, expiring: '1')
    raise Commerce::Error.new('AUTH_INVALID', reason: "shopify_code_http_#{status}") unless status == 200

    credentials = Commerce::Shopify::Tokens.credentials(body)
    ensure_read_only!(credentials['scope'])
    identity = Commerce::Shopify::Oauth.identity(shop, credentials['access_token'])
    Commerce::StoreLock.with('shopify', identity[:external_store_id]) { save(shop, identity, credentials) }
  end

  private

  # Every requested scope granted, and nothing beyond read access: an app configured with more is refused, not used.
  def ensure_read_only!(scope)
    granted = scope.split(',').map(&:strip)
    return if (Commerce::Shopify::Config::SCOPES - granted).empty? && granted.all? { |name| name.start_with?('read_') }

    raise Commerce::Error.new('PERMISSION_DENIED', reason: 'shopify_scopes')
  end

  def save(shop, identity, credentials)
    existing = Commerce::Store.where.not(status: :disconnected).find_by(provider: 'shopify', external_store_id: identity[:external_store_id])
    return reauthorize(existing, shop, credentials) if existing&.account_id == @account.id

    store = @account.commerce_stores.new(provider: 'shopify', base_url: "https://#{shop}", created_by: @user)
    Commerce::StoreConnection.new(account: @account, user: @user).attach(store, identity, credentials, event: 'commerce.shopify.connected')
  end

  # A disabled store stays disabled; any other state becomes active with the new token.
  def reauthorize(store, shop, credentials)
    previous = store.status
    store.update!(base_url: "https://#{shop}", credentials: credentials, status: store.disabled? ? :disabled : :active,
                  metadata: store.metadata.merge('verified_at' => Time.current.iso8601))
    Commerce::AuditTrail.record('commerce.shopify.reauthorized', auditable: store, user: @user, changes: { status: [previous, store.status] })
    store
  end
end
