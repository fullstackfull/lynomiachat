# Lynomia keeps Chatwoot's audit coverage of an inbox after the Enterprise overlay goes: the same declaration,
# included at the same site (app/models/inbox.rb:282), writing to the same `audits` table through Custom::AuditLog.
module Custom::Audit::Inbox
  extend ActiveSupport::Concern

  included do
    audited associated_with: :account, on: [:create, :update]
  end
end
