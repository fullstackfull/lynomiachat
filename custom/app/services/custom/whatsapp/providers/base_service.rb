# The send-side half of package E (docs/p-final/clean-room/specs/E-whatsapp-delivery-status-propagation.md §4.4).
#
# Upstream writes a provider refusal onto the `Message` and returns nothing to the caller, and when there is no
# message it returns before doing even that (app/services/whatsapp/providers/base_service.rb:46). A campaign
# send has no message, so Meta's code and title went to the log and nowhere else -- and package D needs them on
# the recipient, separately, because the recipient list shows the reason and the code as two things.
#
# This keeps the refusal on the instance that saw it. Nothing else changes: `super` still does exactly what it
# did, including the early return, so the conversation-message path is untouched.
module Custom::Whatsapp::Providers::BaseService
  # Meta's cap on the characters a list's own button label may carry.
  LIST_BUTTON_MAX = 20

  # The last refusal this provider instance saw. Readable only for as long as the instance lives, which is why
  # Custom::Channel::Whatsapp keeps one alive across a template send.
  attr_reader :last_send_failure

  def handle_error(response, message)
    @last_send_failure = ::Whatsapp::SendFailure.from_response(response)
    super
  end

  # ORIGINAL LYNOMIA, restored. Lynomia Flow Builder
  # (docs/flow-builder/06-whatsapp-channel-capabilities.md): a flow's List node is always sent as a WhatsApp
  # list -- Chatwoot chooses buttons for three items or fewer without descriptions -- and may name the list's
  # button. Every other input_select message is sent as before.
  #
  # This rode in the same file as the send-failure reader and so was removed with it in PF.CR1, although it was
  # never Enterprise-derived: neither method below, nor LIST_BUTTON_MAX, appears anywhere under `enterprise/` at
  # any of the three pre-removal revisions. It is restored verbatim from this project's own history at
  # `487276f2^`, and it is outside package E, which is about delivery and status propagation only.
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
