# Named Lynomia Flow Builder audit events (docs/flow-builder/08-security-and-tenancy.md §audit), in the Enterprise audit
# log when it is present, as Commerce's are. Creating, renaming and deleting a flow bot are already audited as AgentBot
# changes (Enterprise Audit::AgentBot). Never node transitions, message text or customer data.
module Flows::Audit
  ACTIONS = { 'flow.published' => 'update', 'flow.disabled' => 'update', 'flow.execution.handed_off' => 'update',
              'flow.execution.failed' => 'update' }.freeze

  def self.record(event, agent_bot, user: nil, changes: {})
    Rails.logger.info("[Lynomia::Flow] #{event} account_id=#{agent_bot.account_id} agent_bot_id=#{agent_bot.id} user_id=#{user&.id}")
    return unless defined?(Enterprise::AuditLog)

    Enterprise::AuditLog.create!(auditable: agent_bot, associated: agent_bot.account, user: user, action: ACTIONS.fetch(event),
                                 comment: event, audited_changes: changes)
  end
end
