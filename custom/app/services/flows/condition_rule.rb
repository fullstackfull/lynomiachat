# A flow's conditions (Condition, Audience and Commerce nodes, Start) are Lynomia Automation conditions: the same keys,
# operators, shared audiences and local Commerce summaries (docs/flow-builder/04-node-contracts.md §conditions). They are
# validated and evaluated as an automation rule that is never saved, by the same AutomationRule validation and
# AutomationRules::ConditionsFilterService, for the flow's conversation.
module Flows::ConditionRule
  EVENT = 'conversation_updated'.freeze

  def self.build(account, conditions)
    AutomationRule.new(account: account, name: 'Lynomia flow condition', event_name: EVENT, conditions: conditions, actions: [])
  end

  def self.match?(conversation, conditions)
    AutomationRules::ConditionsFilterService.new(build(conversation.account, conditions), conversation, { changed_attributes: {} }).perform
  end
end
