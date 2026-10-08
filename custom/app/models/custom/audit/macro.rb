# Lynomia keeps Chatwoot's audit coverage of a macro after the Enterprise overlay goes: the same declaration,
# included at the same site (app/models/macro.rb:78), writing to the same `audits` table through Custom::AuditLog.
module Custom::Audit::Macro
  extend ActiveSupport::Concern

  included do
    audited associated_with: :account
  end
end
