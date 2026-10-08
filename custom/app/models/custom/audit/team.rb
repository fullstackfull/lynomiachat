# Lynomia keeps Chatwoot's audit coverage of a team after the Enterprise overlay goes: the same declaration,
# included at the same site (app/models/team.rb:89), writing to the same `audits` table through Custom::AuditLog.
module Custom::Audit::Team
  extend ActiveSupport::Concern

  included do
    audited associated_with: :account
  end
end
