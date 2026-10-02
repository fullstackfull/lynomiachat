# Remove Label: Chatwoot's own label action; removing a label the conversation does not have changes nothing.
class Flows::Nodes::RemoveLabel < Flows::Nodes::AddLabel
  def enter
    ActionService.new(conversation).remove_label(labels)
    Flows::Step.next('next')
  end
end
