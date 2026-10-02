# Assign Team (docs/flow-builder/04-node-contracts.md §assignment): Chatwoot's own team assignment (ActionService), limited
# to the account's teams. The conversation stays with the flow, queued for that team once humans take it. A team deleted
# after the flow was published follows `failed`.
class Flows::Nodes::AssignTeam < Flows::Nodes::Base
  def enter
    team_id = Integer(@data['team_id'].to_s, exception: false)
    ActionService.new(conversation).assign_team([team_id])
    Flows::Step.next(conversation.reload.team_id == team_id ? 'next' : 'failed')
  end
end
