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

  def apply_delivery_report(entry)
    ::Whatsapp::DeliveryReport.new(inbox: inbox, entry: entry).apply
  rescue StandardError => e
    Rails.logger.error("[Lynomia::Whatsapp] could not apply a delivery report on inbox #{inbox.id}: #{e.class}")
    ChatwootExceptionTracker.new(e, account: inbox.account).capture_exception
  end
end
