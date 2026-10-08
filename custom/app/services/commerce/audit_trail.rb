# Named Lynomia Commerce audit events, written to Lynomia's audit log beside the tagged log line.
# Never pass credentials in `changes`.
# `auditable` is a store, a customer link, or the account itself (commerce.salla.connect_started, before any store).
module Commerce::AuditTrail
  # Events without an entry are recorded as 'update': store_enabled, store_disabled, store_needs_reauth, order_actions_changed,
  # action.succeeded, action.failed, action.reconciled,
  # credentials_rotated, customer_link_changed, salla.connect_started, salla.reauthorized, salla.token_refreshed,
  # salla.needs_reauth, zid.reauthorized, zid.token_refreshed, zid.needs_reauth, shopify.reauthorized,
  # shopify.token_refreshed, shopify.needs_reauth, shopify.customer_redacted, shopify.customer_data_requested.
  ACTIONS = {
    'commerce.store_connected' => 'create',
    'commerce.store_disconnected' => 'destroy',
    'commerce.customer_link_created' => 'create',
    'commerce.customer_link_removed' => 'destroy',
    'commerce.action.requested' => 'create',
    'commerce.salla.connected' => 'create',
    'commerce.salla.disconnected' => 'destroy',
    'commerce.zid.connected' => 'create',
    'commerce.shopify.connected' => 'create',
    'commerce.shopify.uninstalled' => 'destroy',
    'commerce.shopify.shop_redacted' => 'destroy'
  }.freeze

  def self.record(event, auditable:, user: nil, changes: {})
    account = auditable.is_a?(Account) ? auditable : auditable.account
    Rails.logger.info("[Commerce] #{event} account_id=#{account.id} #{auditable.class.name}##{auditable.id} user_id=#{user&.id}")
    Custom::AuditLog.create!(
      auditable: auditable, associated: account, user: user,
      action: ACTIONS.fetch(event, 'update'), comment: event, audited_changes: changes
    )
  end
end
