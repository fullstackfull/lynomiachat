# Store lifecycle for account administrators. Any path that stores credentials runs the provider health check with
# them first, so a store is never saved as active with keys that do not work. Audit entries never carry credentials.
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
    identity = adapter.store_identity

    store = Commerce::Store.transaction do
      claim(store, identity[:external_store_id]).tap do |row|
        row.update!(name: name.presence || row.name.presence || identity[:name], credentials: credentials, status: :active,
                    metadata: row.metadata.merge('verified_at' => Time.current.iso8601))
      end
    end
    audit('commerce.store_connected', store, provider: store.provider, external_store_id: store.external_store_id)
    store
  rescue ActiveRecord::RecordNotUnique
    raise Commerce::Error, 'STORE_ALREADY_CONNECTED'
  end

  def rotate_credentials(store, credentials)
    ensure_encryption!
    Commerce::Providers.for(store, credentials: credentials).health
    previous_status = store.status
    store.update!(credentials: credentials, status: :active, metadata: store.metadata.merge('verified_at' => Time.current.iso8601))
    audit('commerce.credentials_rotated', store, status: [previous_status, store.status])
    store
  end

  def enable(store)
    raise Commerce::Error, 'AUTH_INVALID' if store.credentials.blank?

    Commerce::Providers.for(store).health
    store.update!(status: :active, metadata: store.metadata.merge('verified_at' => Time.current.iso8601))
    audit('commerce.store_enabled', store, status: %w[disabled active])
    store
  end

  def disable(store)
    previous_status = store.status
    store.update!(status: :disabled)
    audit('commerce.store_disabled', store, status: [previous_status, 'disabled'])
    store
  end

  # Credentials and customer links are deleted; the row stays (status disconnected) so the store can be reconnected
  # or connected by another account later.
  def disconnect(store)
    links = 0
    store.transaction do
      links = store.customer_links.delete_all
      store.update!(status: :disconnected, credentials: nil)
    end
    audit('commerce.store_disconnected', store, customer_links_removed: links)
    store
  end

  private

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
