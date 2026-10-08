# Lynomia keeps Chatwoot's audit coverage of an automation rule after the Enterprise overlay goes: the same declaration,
# included at the same site (app/models/automation_rule.rb:162), writing to the same `audits` table through Custom::AuditLog.
module Custom::Audit::AutomationRule
  extend ActiveSupport::Concern

  included do
    audited associated_with: :account
  end
end
