# Add Label (docs/flow-builder/04-node-contracts.md §labels): Chatwoot's own label action (ActionService, as Automation and
# Macros run it). Adding a label the conversation already has changes nothing; a label deleted after the flow was
# published is skipped.
class Flows::Nodes::AddLabel < Flows::Nodes::Base
  def enter
    ActionService.new(conversation).add_label(labels)
    Flows::Step.next('next')
  end

  private

  def labels = account.labels.where(title: Array(@data['labels'])).pluck(:title)
end
