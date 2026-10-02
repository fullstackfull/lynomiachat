# Lynomia Flow Builder (docs/flow-builder/06-whatsapp-channel-capabilities.md): a flow's List node is always sent as a
# WhatsApp list (Chatwoot chooses buttons for three items or fewer without descriptions) and may name the list's button.
# Every other input_select message is sent as before.
module Custom::Whatsapp::Providers::BaseService
  LIST_BUTTON_MAX = 20

  def create_payload_based_on_items(message)
    return super unless message.content_attributes['interactive_type'] == 'list'

    create_list_payload(message)
  end

  def create_list_payload(message)
    payload = super
    label = message.content_attributes['list_button'].to_s.strip.first(LIST_BUTTON_MAX)
    return payload if label.empty?

    payload.merge(action: JSON.generate(JSON.parse(payload[:action]).merge('button' => label)))
  end
end
