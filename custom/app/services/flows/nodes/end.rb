# End (docs/flow-builder/04-node-contracts.md §end): the session is completed. The conversation keeps its status unless
# the node says to resolve it (Chatwoot's own status change, as a bot resolving its conversation).
class Flows::Nodes::End < Flows::Nodes::Base
  def enter
    conversation.resolved! if @data['resolve'] == true && !conversation.resolved?
    Flows::Step.finish(:completed)
  end
end
