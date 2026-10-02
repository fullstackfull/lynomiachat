# Assign Agent (docs/flow-builder/04-node-contracts.md §assignment): Chatwoot's own agent assignment (ActionService): only a
# confirmed agent of the inbox, or an administrator, of this account. A human assignee owns the conversation, so the flow
# may still send what follows `next` (for example "Sara will answer you"), and where it would wait or end the conversation
# is handed to that agent. An agent who cannot take it (removed, not in the inbox, unconfirmed) follows `failed`.
class Flows::Nodes::AssignAgent < Flows::Nodes::Base
  def enter
    agent_id = Integer(@data['agent_id'].to_s, exception: false)
    ActionService.new(conversation).assign_agent([agent_id])
    Flows::Step.next(conversation.reload.assignee_id == agent_id ? 'next' : 'failed')
  end
end
