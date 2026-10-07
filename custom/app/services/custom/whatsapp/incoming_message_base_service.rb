# Lynomia Flow Builder (docs/flow-builder/06-whatsapp-channel-capabilities.md): an answer to an interactive message keeps
# the id of the button or list row it chose, next to the visible title Chatwoot already stores as the message text, so a
# flow branches on the option it sent, never on a label. Same Cloud API payload for WhatsApp API and coexistence numbers.
module Custom::Whatsapp::IncomingMessageBaseService
  private

  # Lynomia Campaigns (docs/campaigns/02-recipients.md): Meta reports delivered / read / failed for a campaign's
  # template message against the id the send recorded on the recipient, so a status is a recipient update first and
  # an ordinary message update second. A status that arrives before the recipient's source id is persisted is
  # deferred to Campaigns::UpdateRecipientStatusJob rather than dropped -- but only when it matched no recipient AND
  # no message, because a status for an ordinary conversation message is not a campaign's to reconcile.
  def process_statuses
    status = @processed_params[:statuses].first
    recipient = CampaignRecipient.find_by(account_id: inbox.account_id, inbox_id: inbox.id, source_id: status[:id])
    recipient&.update_from_whatsapp_status!(status)

    super

    return if recipient || @message
    return unless inbox.account.feature_enabled?(:whatsapp_campaign)
    return unless %w[delivered read failed].include?(status[:status].to_s)

    Campaigns::UpdateRecipientStatusJob.set(wait: 2.seconds).perform_later(inbox.id, status.to_h)
  end

  def message_content_attributes(message)
    attributes = super
    reply = message.dig(:interactive, :button_reply) || message.dig(:interactive, :list_reply)
    return attributes if reply.blank? || outgoing_echo

    attributes.merge(interactive_reply: { type: message.dig(:interactive, :type).to_s.first(32), id: reply[:id].to_s.first(256),
                                          title: reply[:title].to_s.first(256) })
  end
end
