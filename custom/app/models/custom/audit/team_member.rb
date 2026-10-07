# Lynomia keeps Chatwoot's audit coverage of team membership after the Enterprise overlay goes. The `audited`
# gem has no hook for a join row's create and destroy, so these are written by hand, as Chatwoot wrote them,
# now through Custom::AuditLog. Included at the site OSS already carries (app/models/team_member.rb).
module Custom::Audit::TeamMember
  extend ActiveSupport::Concern

  included do
    after_commit :create_audit_log_entry_on_create, on: :create
    after_commit :create_audit_log_entry_on_delete, on: :destroy
  end

  private

  def create_audit_log_entry_on_create
    create_audit_log_entry('create')
  end

  def create_audit_log_entry_on_delete
    create_audit_log_entry('destroy')
  end

  def create_audit_log_entry(action)
    return if team.blank?

    Custom::AuditLog.create(
      auditable_id: id,
      auditable_type: 'TeamMember',
      action: action,
      associated_id: team&.account_id,
      audited_changes: attributes.except('updated_at', 'created_at'),
      associated_type: 'Account'
    )
  end
end
