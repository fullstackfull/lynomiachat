# Named Lynomia Commerce audit events. Written to the Enterprise audit log when it is present (Lynomia runs the
# Enterprise overlay); the Community edition keeps the tagged log line only. Never pass credentials in `changes`.
# `auditable` is a store, a customer link, or the account itself (commerce.salla.connect_started, before any store).
module Commerce::AuditTrail
  # Events without an entry are recorded as 'update': store_enabled, store_disabled, store_needs_reauth,
  # credentials_rotated, customer_link_changed, salla.connect_started, salla.reauthorized, salla.token_refreshed,
  # salla.needs_reauth, zid.reauthorized, zid.token_refreshed, zid.needs_reauth, shopify.reauthorized,
  # shopify.token_refreshed, shopify.needs_reauth.
  ACTIONS = {
    'commerce.store_connected' => 'create',
    'commerce.store_disconnected' => 'destroy',
    'commerce.customer_link_created' => 'create',
    'commerce.customer_link_removed' => 'destroy',
    'commerce.salla.connected' => 'create',
    'commerce.salla.disconnected' => 'destroy',
    'commerce.zid.connected' => 'create',
    'commerce.shopify.connected' => 'create'
  }.freeze

  def self.record(event, auditable:, user: nil, changes: {})
    account = auditable.is_a?(Account) ? auditable : auditable.account
    Rails.logger.info("[Commerce] #{event} account_id=#{account.id} #{auditable.class.name}##{auditable.id} user_id=#{user&.id}")
    return unless defined?(Enterprise::AuditLog)

    Enterprise::AuditLog.create!(
      auditable: auditable, associated: account, user: user,
      action: ACTIONS.fetch(event, 'update'), comment: event, audited_changes: changes
    )
  end
end
