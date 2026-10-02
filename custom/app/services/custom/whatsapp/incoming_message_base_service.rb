# Lynomia Flow Builder (docs/flow-builder/06-whatsapp-channel-capabilities.md): an answer to an interactive message keeps
# the id of the button or list row it chose, next to the visible title Chatwoot already stores as the message text, so a
# flow branches on the option it sent, never on a label. Same Cloud API payload for WhatsApp API and coexistence numbers.
module Custom::Whatsapp::IncomingMessageBaseService
  private

  def message_content_attributes(message)
    attributes = super
    reply = message.dig(:interactive, :button_reply) || message.dig(:interactive, :list_reply)
    return attributes if reply.blank? || outgoing_echo

    attributes.merge(interactive_reply: { type: message.dig(:interactive, :type).to_s.first(32), id: reply[:id].to_s.first(256),
                                          title: reply[:title].to_s.first(256) })
  end
end
