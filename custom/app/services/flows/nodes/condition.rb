# Condition (docs/flow-builder/04-node-contracts.md §conditions): Lynomia Automation conditions on the flow's conversation,
# its contact, shared audiences and local Commerce summaries; `true` or `false`. No store is called.
class Flows::Nodes::Condition < Flows::Nodes::Base
  def enter = Flows::Step.next(Flows::ConditionRule.match?(conversation, Array(@data['conditions'])) ? 'true' : 'false')
end
