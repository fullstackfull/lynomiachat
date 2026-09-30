# Named Lynomia Commerce audit events. Written to the Enterprise audit log when it is present (Lynomia runs the
# Enterprise overlay); the Community edition keeps the tagged log line only. Never pass credentials in `changes`.
module Commerce::AuditTrail
  ACTIONS = {
    'commerce.store_connected' => 'create',
    'commerce.store_disconnected' => 'destroy',
    'commerce.customer_link_created' => 'create',
    'commerce.customer_link_removed' => 'destroy'
  }.freeze

  def self.record(event, auditable:, user: nil, changes: {})
    Rails.logger.info("[Commerce] #{event} account_id=#{auditable.account_id} #{auditable.class.name}##{auditable.id} user_id=#{user&.id}")
    return unless defined?(Enterprise::AuditLog)

    Enterprise::AuditLog.create!(
      auditable: auditable, associated: auditable.account, user: user,
      action: ACTIONS.fetch(event, 'update'), comment: event, audited_changes: changes
    )
  end
end
