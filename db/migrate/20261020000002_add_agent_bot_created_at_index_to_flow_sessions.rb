# The five aggregates behind a flow's insights panel -- total, live, by status, by failure code and by
# version -- all run `flow_sessions WHERE agent_bot_id = ? AND created_at >= ?`. No existing index leads
# with agent_bot_id: the closest, (account_id, agent_bot_id, status), cannot serve a query that does not
# name the account, and the association does not. So each panel was five sequential scans over every
# session every account has ever run, and the table grows with traffic rather than with flows.
class AddAgentBotCreatedAtIndexToFlowSessions < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :flow_sessions, [:agent_bot_id, :created_at], algorithm: :concurrently
  end
end
