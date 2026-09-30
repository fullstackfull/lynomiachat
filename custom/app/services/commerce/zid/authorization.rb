# Connects the Zid store behind an authorization code to the account and administrator named by the OAuth state
# (docs/commerce/14-zid-oauth-and-tokens.md). The code is exchanged server-side, the tokens are confirmed against Zid's
# manager profile, and only then is anything saved: a new store through Commerce::StoreConnection's ownership rules (a
# store connected to another account is never moved), or new tokens for this account's own store (re-authorization).
class Commerce::Zid::Authorization
  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def connect(code)
    status, body = Commerce::Zid::Oauth.token(grant_type: 'authorization_code', code: code)
    raise Commerce::Error.new('AUTH_INVALID', reason: "zid_code_http_#{status}") unless status == 200

    credentials = Commerce::Zid::Tokens.credentials(body)
    identity = Commerce::Zid::Oauth.profile(credentials)
    Commerce::StoreLock.with('zid', identity[:external_store_id]) { save(identity, credentials) }
  end

  private

  def save(identity, credentials)
    existing = Commerce::Store.where.not(status: :disconnected).find_by(provider: 'zid', external_store_id: identity[:external_store_id])
    return reauthorize(existing, credentials, identity) if existing&.account_id == @account.id

    store = @account.commerce_stores.new(provider: 'zid', base_url: Commerce::StoreUrl.parse(identity[:base_url]).to_s, created_by: @user,
                                         metadata: { 'time_zone' => identity[:time_zone] })
    Commerce::StoreConnection.new(account: @account, user: @user).attach(store, identity, credentials, event: 'commerce.zid.connected')
  end

  # A disabled store stays disabled; any other state becomes active with the new tokens.
  def reauthorize(store, credentials, identity)
    previous = store.status
    store.update!(credentials: credentials, status: store.disabled? ? :disabled : :active,
                  metadata: store.metadata.merge('verified_at' => Time.current.iso8601, 'time_zone' => identity[:time_zone]))
    Commerce::AuditTrail.record('commerce.zid.reauthorized', auditable: store, user: @user, changes: { status: [previous, store.status] })
    store
  end
end
