# WHAT ACTUALLY BECAME OF A MESSAGE, TOLD TO THE PARTNER THAT ASKED FOR IT.
#
# THE GAP THIS CLOSES. `POST /api/v1/accounts/:id/conversations/:id/messages` answers 200 the
# moment the message ROW exists. The provider call happens afterwards in SendReplyJob, and so
# do the platform workspace's UTILITY gate, the consent gate and the allowance meter. A partner
# that treated the 200 as a send therefore recorded "sent" for messages this side went on to
# refuse, and nothing ever told it otherwise -- there was no delivery callback at all.
#
# A SEPARATE EVENT, NOT `message_updated`. That event exists and fires on every message update,
# but `Message#webhook_data` carries no `status` field, so a subscriber cannot tell delivered
# from failed from it; and it fires on content edits too, which is noise on a feed whose whole
# purpose is outcomes. This one carries the outcome and fires only when the outcome changes.
#
# THE SAME PIPE AS Consents::ChangeFeed, through the same Partner::EventFan: the same account
# webhook subscription, the same after-commit enqueue, and the same rule that a delivery id is
# derived from the fact rather than minted, so a republication is a no-op at a receiver that
# dedupes on it. What differs is this file -- the vocabulary, the payload and the derivation --
# and that is the only thing that should.
#
# THE ACCOUNT TRAVELS IN THE PAYLOAD because the receiver checks it: a signature proves who
# sent a delivery, the account proves what it is allowed to talk about.
#
# WHAT IT DOES NOT CLAIM. Lynomia knows four states for a message and `sent` is the column
# default, written before anything is attempted. So `sent` alone is never reported as a send:
# the outcome below is derived from the status TOGETHER with whether the provider gave us an
# id, and a message with neither is `queued`, which is the honest word for "this side has it
# and nothing has happened yet".
module Delivery::StatusFeed
  EVENT = 'message_delivery_status'.freeze

  # The partner-facing vocabulary. Deliberately NOT Lynomia's enum: a partner needs to tell a
  # policy refusal from a provider failure, and `failed` means both here.
  QUEUED = 'queued'.freeze
  PROVIDER_ACCEPTED = 'provider_accepted'.freeze
  DELIVERED = 'delivered'.freeze
  READ = 'read'.freeze
  FAILED = 'failed'.freeze
  REFUSED = 'refused'.freeze

  # Refusals this installation decides for itself, before or instead of a provider call. The
  # keys are the i18n suffixes Custom::Whatsapp::SendOnWhatsappService writes, which is the one
  # place that writes them, so a new gate appears here by being added there.
  ELIGIBILITY_REASONS = %w[
    platform_promotional_refused platform_allowance_exhausted platform_allowance_unset
    contact_unavailable consent_withdrawn messaging_suppressed promotional_consent_missing
  ].freeze

  module_function

  # Called from Custom::Message's after_update_commit when `status` changed, which is the one
  # hook every writer passes through -- Messages::StatusUpdateService, the provider's own
  # failure write, and the eligibility gates, which update the row directly and would bypass a
  # hook placed on the status service.
  def publish(message)
    return if message.account.nil?
    return unless message.outgoing?

    Partner::EventFan.publish(message.account, EVENT, payload(message),
                              delivery_id: "delivery-#{message.id}-#{occurred_at_us(message)}")
  end

  def payload(message)
    {
      event: EVENT,
      # The account travels because the receiver checks it: a signature proves who sent a
      # delivery, this proves what it is allowed to talk about.
      account: { id: message.account_id },
      message: { id: message.id, source_id: message.source_id, conversation_id: message.conversation&.display_id },
      # Lynomia's own enum, unchanged, so a reader who wants the raw fact has it.
      status: message.status,
      outcome: outcome_of(message),
      reason_code: reason_code(message),
      occurred_at: message.updated_at.utc.iso8601(6),
      # THE ORDERING KEY, as an integer, because that is what the receiver compares. A late
      # delivery receipt arriving after a newer one must not overwrite it, and comparing
      # formatted timestamps across two languages' parsers is how that goes wrong.
      occurred_at_us: occurred_at_us(message)
    }
  end

  # WHAT HAPPENED, as far as this side can honestly say.
  #
  # `sent` is the column default and is written on INSERT, before anything is attempted, so it
  # cannot mean the provider took the message. What distinguishes the two is `source_id`: the
  # provider's own id for the message, written only when it answered.
  def outcome_of(message)
    case message.status
    when 'delivered' then DELIVERED
    when 'read' then READ
    when 'failed' then eligibility_refusal?(message) ? REFUSED : FAILED
    else message.source_id.present? ? PROVIDER_ACCEPTED : QUEUED
    end
  end

  # A refusal this installation decided, rather than one the provider returned. The eligibility
  # gates write a localized sentence into external_error, so the code is recovered by asking
  # which of them produced that sentence rather than by parsing it.
  # ALWAYS A STRING. The eligibility reasons are words and Meta's codes are integers, and a
  # field that is sometimes one and sometimes the other is a field every consumer has to guess
  # at. A reason code is an identifier, not a quantity, so it travels as text.
  def reason_code(message)
    return nil unless message.status == 'failed'

    (eligibility_reason(message) || Whatsapp::DeliveryFailure.for(message).code)&.to_s.presence
  end

  def eligibility_refusal?(message) = eligibility_reason(message).present?

  def eligibility_reason(message)
    error = message.external_error.to_s
    return nil if error.blank?

    ELIGIBILITY_REASONS.find { |reason| I18n.t("errors.whatsapp.consent.#{reason}") == error }
  end

  def occurred_at_us(message) = (message.updated_at.to_f * 1_000_000).round
end
