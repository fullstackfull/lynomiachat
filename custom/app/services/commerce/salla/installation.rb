# Applies a verified Salla app event (docs/commerce/10-salla-install-correlation.md).
#
# Salla's Easy Mode delivers a store's tokens in `app.store.authorize`, which names the merchant but no Lynomia account,
# so an installation never attaches itself to an account. The account is proven by a connection code
# (Commerce::Salla::ConnectionCode) that the merchant enters in the app's settings in their Salla dashboard and that Salla
# delivers, signed, in `app.settings.updated`. The two events arrive in either order: each waits for the other (7 days,
# tokens encrypted), then the store is connected. A store that is already connected takes the tokens of any later
# authorization (app update, reinstall); a store connected to another account is never moved.
#
# Everything for one merchant runs under Commerce::StoreLock, as token refreshes do.
class Commerce::Salla::Installation
  PENDING_TTL = 7.days
  CODE_SETTING = 'lynomia_connection_code'.freeze

  def initialize(payload)
    @event = payload['event']
    @merchant_id = merchant_id(payload['merchant'])
    @data = payload['data'] || {}
  end

  def process
    case @event
    when 'app.store.authorize' then authorize
    when 'app.settings.updated' then claim
    when 'app.uninstalled' then uninstall
    end
  end

  private

  # With Salla switched off, only stores that are already connected keep their tokens current.
  def authorize
    credentials = Commerce::Salla::Tokens.credentials(@data)
    return unless Commerce::Salla::Config.enabled? || connected_store

    identity = Commerce::Salla::Oauth.user_info(credentials['access_token'])
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'salla_merchant_mismatch') unless identity[:external_store_id] == @merchant_id

    lock do
      store = connected_store
      if store
        reauthorize(store, credentials, identity)
      elsif Commerce::Salla::Config.enabled?
        Redis::SecureStorage.set(tokens_key, { credentials: credentials, identity: identity }, PENDING_TTL)
        complete
      end
    end
  end

  def claim
    code = @data.fetch('settings', {})[CODE_SETTING]
    return unless code.is_a?(String) && code.present? && Commerce::Salla::Config.enabled?

    attempt = Commerce::Salla::ConnectionCode.redeem(code)
    return Rails.logger.warn("[Commerce:salla] connection code not accepted merchant=#{@merchant_id}") if attempt.nil?

    lock do
      store = connected_store
      next claim_connected(store, attempt['account_id']) if store

      Redis::Alfred.setex(claim_key, attempt.to_json, PENDING_TTL)
      complete
    end
  end

  # A code for a store that is already connected: nothing to do for its own account, a conflict for any other, since a
  # connected store is never moved.
  def claim_connected(store, account_id)
    return Commerce::Salla::ConnectionCode.finish(account_id, 'connected', store_id: store.id) if store.account_id == account_id

    Rails.logger.warn("[Commerce:salla] merchant=#{@merchant_id} belongs to another account; claim by account_id=#{account_id} refused")
    Commerce::Salla::ConnectionCode.finish(account_id, 'conflict')
  end

  # The store is disconnected (credentials, customer links and cached data deleted); contacts and conversations stay.
  def uninstall
    lock do
      Redis::SecureStorage.delete(tokens_key)
      Redis::Alfred.delete(claim_key)
      store = connected_store
      Commerce::StoreConnection.new(account: store.account, user: nil).disconnect(store, event: 'commerce.salla.disconnected') if store
    end
  end

  # Connects the store once both halves are here: the tokens and an account's claim.
  def complete
    claim = JSON.parse(Redis::Alfred.get(claim_key) || 'null')
    pending = Redis::SecureStorage.get(tokens_key)
    return unless claim && pending

    store = connect(Account.find(claim['account_id']), claim['user_id'], JSON.parse(pending))
    Redis::SecureStorage.delete(tokens_key)
    Redis::Alfred.delete(claim_key)
    Commerce::Salla::ConnectionCode.finish(store.account_id, 'connected', store_id: store.id)
  end

  def connect(account, user_id, pending)
    identity = pending['identity'].symbolize_keys
    user = account.users.find_by(id: user_id)
    store = account.commerce_stores.new(provider: 'salla', base_url: Commerce::StoreUrl.parse(identity[:domain]).to_s, created_by: user,
                                        metadata: { 'authorized_by_salla_user_id' => identity[:user_id] })
    Commerce::StoreConnection.new(account: account, user: user).attach(store, identity, pending['credentials'], event: 'commerce.salla.connected')
  end

  def reauthorize(store, credentials, identity)
    previous = store.status
    store.update!(credentials: credentials, status: store.disabled? ? :disabled : :active,
                  metadata: store.metadata.except('refresh_started_at')
                                 .merge('verified_at' => Time.current.iso8601, 'authorized_by_salla_user_id' => identity[:user_id]))
    Commerce::AuditTrail.record('commerce.salla.reauthorized', auditable: store, changes: { status: [previous, store.status] })
  end

  def connected_store
    Commerce::Store.where.not(status: :disconnected).find_by(provider: 'salla', external_store_id: @merchant_id)
  end

  def lock(&)
    Commerce::StoreLock.with('salla', @merchant_id, &)
  end

  def tokens_key = "COMMERCE::SALLA::MERCHANT::#{@merchant_id}::TOKENS"

  def claim_key = "COMMERCE::SALLA::MERCHANT::#{@merchant_id}::CLAIM"

  def merchant_id(value)
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'salla_merchant') unless value.is_a?(Integer) && value.positive?

    value.to_s
  end
end
