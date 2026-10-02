# Human Handoff (docs/flow-builder/04-node-contracts.md §handoff): routes the conversation with Chatwoot's own actions
# (ActionService: team, agent of the inbox, priority, labels; each optional), leaves the merchant's reason as a private
# note for the agents, and ends the session: Chatwoot's bot handoff opens the conversation and the flow never answers it
# again in this session.
class Flows::Nodes::Handoff < Flows::Nodes::Base
  def enter
    route(ActionService.new(conversation))
    note if @data['reason'].present?
    Flows::Step.finish(:handed_off, code: 'handoff_node')
  end

  private

  def route(actions)
    actions.assign_team([Integer(@data['team_id'].to_s)]) if @data['team_id'].present?
    actions.assign_agent([Integer(@data['agent_id'].to_s)]) if @data['agent_id'].present?
    actions.change_priority([@data['priority']]) if @data['priority'].present?
    actions.add_label(account.labels.where(title: Array(@data['labels'])).pluck(:title)) if @data['labels'].present?
  end

  def note
    conversation.messages.create!(message_type: :outgoing, private: true, account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                  sender: @run.bot, content: @data['reason'].to_s.first(255))
  end
end
