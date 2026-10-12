# The inbound half of package E (docs/p-final/clean-room/specs/E-whatsapp-delivery-status-propagation.md).
#
# Upstream abandons a delivery report whose identifier matches no `Message`
# (app/services/whatsapp/incoming_message_base_service.rb:64). A campaign send creates no message, so without
# this every campaign recipient stays at "sent" for ever and package D's numbers report nothing but sends.
#
# `super` first and unchanged, so the conversation-message path runs exactly when and how it ran before -- same
# lock, same forward-only rule in Messages::StatusUpdateService, same identifier updates. Then every entry in
# the payload is offered to the recipient router. An identifier belongs to at most one of the two, so offering
# all of them to the recipient path cannot touch a message: upstream handles only the first entry of a batch,
# and the entries it drops are ones no message ever owned.
#
# Each entry is contained on its own. Meta retries any delivery that does not return success, so one entry that
# cannot be applied must not fail the request and take the other entries -- and the whole payload -- down with
# it into a retry loop.
module Custom::Whatsapp::IncomingMessageBaseService
  def process_statuses
    super

    Array(processed_params[:statuses]).each { |entry| apply_delivery_report(entry) }
  end

  private

  # ORIGINAL LYNOMIA, restored. Lynomia Flow Builder
  # (docs/flow-builder/06-whatsapp-channel-capabilities.md): an answer to an interactive message keeps the id of
  # the button or list row it chose, next to the visible title Chatwoot already stores as the message text, so a
  # flow branches on the option it sent, never on a label. Same Cloud API payload for WhatsApp API and
  # coexistence numbers.
  #
  # This rode in the same file as the campaign status hook and so was removed with it in PF.CR1, although it was
  # never Enterprise-derived: neither method below appears anywhere under `enterprise/` at any of the three
  # pre-removal revisions. It is restored verbatim from this project's own history at `487276f2^`, and it is
  # outside package E, which excludes inbound message handling
  # (docs/p-final/clean-room/specs/E-whatsapp-delivery-status-propagation.md §9).
  def message_content_attributes(message)
    attributes = super
    reply = message.dig(:interactive, :button_reply) || message.dig(:interactive, :list_reply)
    return attributes if reply.blank? || outgoing_echo

    attributes.merge(interactive_reply: { type: message.dig(:interactive, :type).to_s.first(32), id: reply[:id].to_s.first(256),
                                          title: reply[:title].to_s.first(256) })
  end

  def apply_delivery_report(entry)
    ::Whatsapp::DeliveryReport.new(inbox: inbox, entry: entry).apply
  rescue StandardError => e
    Rails.logger.error("[Lynomia::Whatsapp] could not apply a delivery report on inbox #{inbox.id}: #{e.class}")
    ChatwootExceptionTracker.new(e, account: inbox.account).capture_exception
  end
end
