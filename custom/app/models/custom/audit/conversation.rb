# Lynomia keeps Chatwoot's audit coverage of a deleted conversation after the Enterprise overlay goes: the same declaration,
# included at the same site (app/models/conversation.rb:434), writing to the same `audits` table through Custom::AuditLog.
module Custom::Audit::Conversation
  extend ActiveSupport::Concern

  included do
    audited only: [], on: [:destroy]
  end
end
