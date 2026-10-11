# Recording what a one-off WhatsApp campaign did to each contact it addressed
# (docs/p-final/clean-room/specs/D-campaign-recipient-outcomes.md §4.1).
#
# Upstream's send loop already makes every decision this has to record: it refuses a contact with no reachable
# WhatsApp destination, refuses one whose template variables resolve to blank, hands the rest to Meta, and
# continues past a per-contact failure. What it does not do is write any of that down, so the operator who sent
# the campaign cannot see who it reached.
#
# The decisions are therefore recorded where upstream makes them, rather than by re-expressing its loop here:
# each hook below records one outcome and delegates. Two consequences are deliberate:
#
# * **The campaign still completes when one contact fails.** Nothing here raises, and the recording of an
#   outcome is contained so that a store problem cannot abort a run that has already handed messages to Meta.
# * **A contact upstream refused at a point with no hook of its own still gets a row.** `#process_contact`
#   checks for an outcome afterwards and records the remaining reason, so the snapshot has one row per
#   addressed contact whatever happened to it -- which is what makes `audience` the denominator every rate in
#   the interface is computed against.
#
# Skip reasons are the fixed strings on Campaigns::RecipientSnapshot and carry no contact data: P8 groups its
# skip breakdown on that column directly, so a reason containing a phone number would both explode the
# breakdown's cardinality and put recipient data into an analytics response.
module Custom::Whatsapp::OneoffCampaignService
  def process_contact(contact)
    @contact = contact
    @outcome = nil
    super
    record(:skipped, unhooked_reason) if @outcome.nil?
  ensure
    @contact = nil
  end

  private

  # [recipient, error]. A blank recipient is upstream's way of saying it found no WhatsApp destination it was
  # willing to use, and the two cases are different problems for the operator: fix the contact's data, or
  # decide which of its identities the campaign should address. Upstream has already told them apart, so its
  # own classification is read rather than re-derived.
  def campaign_destination(contact)
    super.tap do |recipient, error|
      next if recipient.present?

      record(:skipped, destination_reason(error))
    end
  end

  # nil means Liquid resolved a variable to blank for this contact, or raised while trying. Either way nothing
  # was sent, and the remedy is the contact's data or the template's defaults.
  def process_liquid_template_params(contact)
    super.tap do |params|
      record(:skipped, Campaigns::RecipientSnapshot::BLANK_TEMPLATE_VARIABLES) if params.nil?
    end
  end

  def authentication_template_blocked?(recipient, params)
    super.tap do |blocked|
      record(:skipped, Campaigns::RecipientSnapshot::AUTHENTICATION_TEMPLATE_BLOCKED) if blocked
    end
  end

  # The rendered text is computed before the send because it is what was sent, whether or not Meta accepted it:
  # an operator diagnosing a refusal needs to see the message that was refused.
  #
  # Three outcomes, told apart by what the channel is left holding. An identifier means Meta accepted it. A
  # refusal means Meta, or the network, said no -- and that refusal is only reachable at all because
  # Custom::Channel::Whatsapp keeps the provider instance alive across the call. Neither means no provider call
  # was made: upstream found no approved template of that name and language, so nothing was attempted.
  def send_whatsapp_template_message(to:, template_params:)
    text = Campaigns::RenderedTemplateText.new(channel: channel, template_params: template_params).text
    source_id = super
    return source_id if @outcome.present?

    if source_id.present?
      record_sent(source_id, text)
    elsif (failure = channel.last_send_failure).present?
      record_failure(failure, text)
    else
      record(:skipped, Campaigns::RecipientSnapshot::TEMPLATE_NOT_AVAILABLE, message_content: text)
    end

    source_id
  end

  # Upstream's two refusals are "Phone number and BSUID are missing" and "Multiple WhatsApp identities found;
  # refusing to choose a destination" (app/services/whatsapp/oneoff_campaign_service.rb:121,126). Only the
  # second is about having too many, so that is what is matched on; anything else is the commoner case of
  # having none.
  AMBIGUITY_IN_REASON = /multiple/i

  def destination_reason(error)
    return Campaigns::RecipientSnapshot::AMBIGUOUS_DESTINATION if error.to_s.match?(AMBIGUITY_IN_REASON)

    Campaigns::RecipientSnapshot::NO_DESTINATION
  end

  # The one reason upstream decides without passing through any method of its own: it checks
  # `campaign.template_params.blank?` inline (app/services/whatsapp/oneoff_campaign_service.rb:51).
  def unhooked_reason
    Campaigns::RecipientSnapshot::NO_TEMPLATE_PARAMS
  end

  def record(outcome, reason, message_content: nil)
    contained(outcome) { snapshot.skipped(@contact, reason, message_content: message_content) }
  end

  def record_sent(source_id, message_content)
    contained(:sent) { snapshot.sent(@contact, source_id: source_id, message_content: message_content) }
  end

  def record_failure(failure, message_content)
    contained(:failed) do
      snapshot.failed(@contact, message_content: message_content, error_code: failure&.code,
                                error_title: failure&.title, error_message: failure&.message)
    end
  end

  # A send already handed to Meta cannot be unsent, so a failure to record must never make the run look
  # incomplete when it was not (package D §6). It is loud in the log instead.
  def contained(outcome)
    return if @contact.blank?

    @outcome = outcome
    yield
  rescue StandardError => e
    Rails.logger.error("[Lynomia::Campaigns] campaign #{campaign.id} could not record contact #{@contact&.id}: #{e.class}")
    ChatwootExceptionTracker.new(e, account: campaign.account).capture_exception
  end

  def snapshot
    @snapshot ||= Campaigns::RecipientSnapshot.new(campaign)
  end
end
