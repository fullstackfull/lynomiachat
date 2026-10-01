# Store lifecycle, for account administrators and Salla installation events. Credentials are saved only once verified
# (WooCommerce keys by the provider health check, Salla tokens by a signed installation confirmed with Salla), so a store
# is never saved as active with credentials that do not work. Audit entries never carry credentials.
class Commerce::StoreConnection
  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def connect(provider:, base_url:, credentials:, name: nil)
    ensure_encryption!
    store = @account.commerce_stores.new(provider: provider, base_url: Commerce::StoreUrl.parse(base_url).to_s, created_by: @user)
    adapter = Commerce::Providers.for(store, credentials: credentials)
    adapter.health
    attach(store, adapter.store_identity, credentials, name: name)
  end

  # Saves a connection whose store identity and credentials are already verified: by the health check in #connect, or
  # for Salla by a signed installation confirmed with Salla (Commerce::Salla::Installation). The new store's metadata is
  # kept when an earlier row of the same store is reused.
  def attach(store, identity, credentials, name: nil, event: 'commerce.store_connected')
    ensure_encryption!
    store = Commerce::Store.transaction do
      claim(store, identity[:external_store_id]).tap do |row|
        row.update!(name: name.presence || row.name.presence || identity[:name], credentials: credentials, status: :active,
                    metadata: row.metadata.merge(store.metadata, 'verified_at' => Time.current.iso8601))
      end
    end
    audit(event, store, provider: store.provider, external_store_id: store.external_store_id)
    store
  rescue ActiveRecord::RecordNotUnique
    raise Commerce::Error, 'STORE_ALREADY_CONNECTED'
  end

  def rotate_credentials(store, credentials)
    ensure_encryption!
    Commerce::Providers.for(store, credentials: credentials).health
    previous_status = store.status
    store.update!(credentials: credentials, status: :active, metadata: store.metadata.merge('verified_at' => Time.current.iso8601))
    Commerce::Cache.purge(store)
    audit('commerce.credentials_rotated', store, status: [previous_status, store.status])
    store
  end

  def enable(store)
    raise Commerce::Error, 'PROVIDER_DISABLED' unless Commerce::Providers.enabled?(store.provider)
    raise Commerce::Error, 'AUTH_INVALID' if store.credentials.blank?

    Commerce::Providers.for(store).health
    store.update!(status: :active, metadata: store.metadata.merge('verified_at' => Time.current.iso8601))
    audit('commerce.store_enabled', store, status: %w[disabled active])
    store
  end

  # The store answered that its credentials no longer work: it is flagged for an administrator and its cached data is
  # dropped, so nothing is shown from it until it is authorized again.
  def credentials_rejected(store)
    return unless store.active?

    store.update!(status: :needs_reauth)
    Commerce::Cache.purge(store)
    audit('commerce.store_needs_reauth', store, {})
  end

  def disable(store)
    previous_status = store.status
    store.update!(status: :disabled)
    Commerce::Cache.purge(store)
    audit('commerce.store_disabled', store, status: [previous_status, 'disabled'])
    store
  end

  # Credentials, customer links and cached store data are deleted; the row stays (status disconnected) so the store can be reconnected
  # or connected by another account later. Contacts and conversations are kept.
  def disconnect(store, event: 'commerce.store_disconnected')
    release(store)
    links = 0
    store.transaction do
      links = store.customer_links.delete_all
      store.update!(status: :disconnected, credentials: nil)
    end
    Commerce::Cache.purge(store)
    audit(event, store, customer_links_removed: links)
    store
  end

  private

  # What the provider set up in the store for Lynomia is removed while the credentials still exist. Best effort: a store
  # that cannot be reached is disconnected anyway.
  def release(store)
    Commerce::Providers.for(store).release if store.credentials.present?
  rescue Commerce::Error => e
    Rails.logger.warn("[Commerce:#{store.provider}] release failed store=#{store.id} code=#{e.code}")
  end

  def ensure_encryption!
    raise Commerce::Error, 'ENCRYPTION_NOT_CONFIGURED' unless Chatwoot.encryption_configured?
  end

  # One account owns a store. Reconnecting in the same account reuses the disconnected row; a store another account
  # disconnected is released to this one; anything else is already connected.
  def claim(store, external_store_id)
    existing = Commerce::Store.find_by(provider: store.provider, external_store_id: external_store_id)
    store.external_store_id = external_store_id
    return store if existing.nil?
    raise Commerce::Error, 'STORE_ALREADY_CONNECTED' unless existing.disconnected?
    return existing.tap { |row| row.base_url = store.base_url } if existing.account_id == @account.id

    existing.destroy!
    store
  end

  def audit(event, store, changes)
    Commerce::AuditTrail.record(event, auditable: store, user: @user, changes: changes)
  end
end
