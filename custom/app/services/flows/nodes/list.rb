# List: up to ten rows with optional descriptions, always sent as a WhatsApp list, with the node's button label.
class Flows::Nodes::List < Flows::Nodes::Choice
  private

  def extra_attributes = { 'interactive_type' => 'list', 'list_button' => @data['button_label'] }.compact_blank
end
