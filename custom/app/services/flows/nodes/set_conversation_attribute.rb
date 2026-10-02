class Flows::Nodes::SetConversationAttribute < Flows::Nodes::SetAttribute
  private

  def attribute_model = 'conversation_attribute'

  def target = conversation
end
