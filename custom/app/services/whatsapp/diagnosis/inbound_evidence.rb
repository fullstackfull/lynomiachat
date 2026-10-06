# frozen_string_literal: true

# The CONTACT TEST section of a Lynomia WhatsApp diagnosis: what this installation's own database says about
# WhatsApp traffic on an inbox, and what the code therefore believes about the 24-hour customer service window.
#
# This is the most informative part of the report, because it separates the two explanations that look identical
# from the outside: "Meta never delivered anything to us" and "we received it and dropped it later". It also shows
# why a broken inbound presents as an outbound problem — see NO_INBOUND_NOTE.
#
# Reads only. Timestamps and counts, never a message body.
class Whatsapp::Diagnosis::InboundEvidence
  NO_INBOUND_NOTE = 'If zero, the customer -> Meta -> Lynomia path is not completing. Note the knock-on effect: ' \
                    'Conversations::MessageWindowService treats a WhatsApp conversation with no persisted incoming ' \
                    'message as OUTSIDE the 24-hour window, so Whatsapp::SendOnWhatsappService fails a plain-text ' \
                    'reply locally with "message_outside_messaging_window" WITHOUT calling Meta. A broken inbound ' \
                    'therefore also presents as "cannot send to a new contact".'

  STUCK_NOTE = 'Outbound messages that never leave `sent` mean Meta\'s delivery STATUS callbacks are not being ' \
               'ingested either. Statuses arrive on the same `messages` webhook field as customer messages, so ' \
               'this points at the WEBHOOK section rather than at the send path.'

  def initialize(report, contact_identifier: nil)
    @report = report
    @contact_identifier = contact_identifier
  end

  def run(inbox)
    report.heading("CONTACT TEST — inbox ##{inbox.id}")
    incoming = Message.where(inbox_id: inbox.id, message_type: :incoming)
    outgoing = Message.where(inbox_id: inbox.id, message_type: :outgoing)
    message_counts(incoming, outgoing)
    recent = incoming.where(created_at: 7.days.ago..).count
    report.check("inbox ##{inbox.id}: an inbound message has been persisted in the last 7 days", recent.positive?,
                 recent.to_s, note: NO_INBOUND_NOTE)
    outbound_status_mix(inbox, outgoing)
    last_provider_failure(outgoing)
    window(inbox)
  end

  private

  attr_reader :report

  def message_counts(incoming, outgoing)
    report.say "incoming messages ever: #{incoming.count}, outgoing: #{outgoing.count}"
    report.say "last incoming: #{describe_last(incoming)}"
    report.say "last outgoing: #{describe_last(outgoing)}"
    report.say "incoming in the last 24h: #{incoming.where(created_at: 24.hours.ago..).count}"
  end

  def describe_last(scope)
    message = scope.order(created_at: :desc).first
    message ? "#{message.created_at.iso8601} (id #{message.id})" : 'NEVER'
  end

  # Whether delivery statuses are arriving at all. A column of `sent` with no `delivered` is the signature of a
  # webhook path that is not ingesting the `messages` field.
  def outbound_status_mix(inbox, outgoing)
    recent = outgoing.where(created_at: 7.days.ago..)
    total = recent.count
    return report.say('outbound status mix, last 7 days: none') if total.zero?

    mix = Message.statuses.keys.index_with { |status| recent.where(status: status).count }
    report.say "outbound status mix, last 7 days: #{describe_mix(mix)}"
    delivered = mix['delivered'].to_i + mix['read'].to_i
    report.check("inbox ##{inbox.id}: outbound messages are reaching delivered/read", delivered.positive?,
                 "delivered+read=#{delivered} of #{total}", note: STUCK_NOTE)
  end

  def describe_mix(mix)
    mix.reject { |_, count| count.zero? }.map { |status, count| "#{status}=#{count}" }.join(' ')
  end

  # The agent-visible reason a send failed. P5 Part I asks that Meta's specific reason not be flattened into
  # "message failed", so the last few are printed verbatim — `external_error` holds Meta's own code and title, or
  # the local 24-hour-window refusal, and the two must stay distinguishable.
  def last_provider_failure(outgoing)
    failed = outgoing.where(status: :failed).where(created_at: 7.days.ago..)
    report.say "failed outgoing in the last 7 days: #{failed.count}"
    failed.order(created_at: :desc).limit(5).each do |message|
      report.say "  #{message.created_at.iso8601} failed: #{message.external_error.to_s[0, 200]}"
    end
  end

  # The window as the code computes it, for the contact the operator names. This is what discriminates the old
  # contact that can be messaged from the new contact that cannot.
  def window(inbox)
    return if @contact_identifier.blank?

    normalized = Contacts::Phone.e164(@contact_identifier)
    return report.say(unnormalizable_note) if normalized.blank?

    report.say "contact lookup for #{report.mask_phone(normalized)}"
    contact = inbox.account.contacts.find_by(phone_number: normalized)
    contact ? contact_windows(inbox, contact) : report.say('  no contact with that phone number in this account')
  end

  # The operator's own CONTACT= value reaches this line, and a value that failed normalization is exactly the
  # case where it is a bare local number — so it is masked like every other number in the report rather than
  # echoed back into something that gets pasted into an issue.
  def unnormalizable_note
    "contact lookup skipped: #{report.mask_phone(@contact_identifier)} is not a number this installation can " \
      'normalize without an explicit country (app/services/contacts/phone.rb). Give it in full international form.'
  end

  def contact_windows(inbox, contact)
    conversations = contact.conversations.where(inbox_id: inbox.id)
    report.say "  contact id=#{contact.id}, conversations in this inbox: #{conversations.count}"
    return report.say('  no conversation exists for this contact in this inbox') if conversations.empty?

    conversations.order(created_at: :desc).limit(3).each { |conversation| conversation_window(conversation) }
  end

  def conversation_window(conversation)
    last_incoming = conversation.messages.incoming.order(created_at: :desc).first
    last_outgoing = conversation.messages.outgoing.order(created_at: :desc).first
    can_reply = Conversations::MessageWindowService.new(conversation).can_reply?
    report.say "  conversation ##{conversation.display_id}: " \
               "last_incoming=#{last_incoming ? last_incoming.created_at.iso8601 : 'NEVER'} " \
               "last_outgoing=#{last_outgoing ? last_outgoing.created_at.iso8601 : 'NEVER'} " \
               "can_reply?=#{can_reply} (24h window #{can_reply ? 'OPEN' : 'CLOSED'})"
    return if can_reply

    report.say '    can_reply? false means Lynomia refuses a plain-text reply before Meta is called; only an ' \
               'approved template can open this conversation. That refusal is a LOCAL decision, not a Meta ' \
               'delivery failure, and the message\'s external_error says so.'
  end
end
