# Lynomia keeps Chatwoot's audit coverage of an agent bot after the Enterprise overlay goes: the same declaration,
# included at the same site (app/models/agent_bot.rb:72), writing to the same `audits` table through Custom::AuditLog.
module Custom::Audit::AgentBot
  extend ActiveSupport::Concern

  included do
    audited associated_with: :account, except: [:secret]
  end
end
