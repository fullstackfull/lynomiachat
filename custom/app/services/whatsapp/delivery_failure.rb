# What a Meta delivery failure means, and whether re-sending the same message can possibly help.
#
# Lynomia already records Meta's refusal verbatim as `"<code>: <title>"`
# (Whatsapp::IncomingMessageBaseService#update_message_with_status) and has always left the meaning to whoever read
# it. That is enough for a person and not enough for the retry path: a refusal scoped to the RECIPIENT is one Meta
# will give again for the same message to the same person, so offering Retry invites an operator to hammer someone
# Meta has deliberately throttled — and each attempt is another quality signal against the number.
#
# Only codes this installation has actually observed on its own traffic are classified. Everything else is
# UNCLASSIFIED and behaves exactly as it did before, because transcribing Meta's catalogue from memory would be
# inventing policy that nothing here can stand behind.
#
#   131049  recipient  Meta withheld a marketing message from one person to cap how many they receive. Observed
#                      interleaved with delivered/read messages on the same inbox, WABA, token and code path in the
#                      same minutes, which is what proves it is per-recipient and not a transport fault.
#   131042  account    the WhatsApp Business account's currency or payment method is not usable. An operator CAN
#                      fix this outside Lynomia, so the same message may later send — a retry stays available.
#
# This class decides nothing about Meta and changes nothing at Meta. It reads a string Lynomia already stored.
class Whatsapp::DeliveryFailure
  RECIPIENT_DELIVERY_RESTRICTION = 'META_RECIPIENT_DELIVERY_RESTRICTION'.freeze
  BILLING_ELIGIBILITY = 'META_BILLING_ELIGIBILITY'.freeze
  UNCLASSIFIED = 'UNCLASSIFIED'.freeze

  DO_NOT_AUTO_RETRY = 'DO_NOT_AUTO_RETRY'.freeze
  AUTO_RETRY_UNDEFINED = 'AUTO_RETRY_UNDEFINED'.freeze

  CODES = {
    131_049 => { classification: RECIPIENT_DELIVERY_RESTRICTION, scope: :recipient },
    131_042 => { classification: BILLING_ELIGIBILITY, scope: :account }
  }.freeze

  # Only a leading `<digits>:` counts, which is the shape Lynomia itself writes. A localized refusal such as the
  # 24-hour window message carries no code and is therefore never mistaken for one of Meta's.
  CODE_IN_ERROR = /\A(\d{3,6}):/

  attr_reader :code

  def initialize(external_error)
    @code = external_error.to_s[CODE_IN_ERROR, 1]&.to_i
  end

  def self.for(message) = new(message.try(:external_error))

  def classified? = entry.present?
  def classification = entry ? entry[:classification] : UNCLASSIFIED

  # Nothing in Lynomia auto-retries a WhatsApp send today — a refusal is saved and the job ends without raising —
  # and for these codes that is the correct behaviour rather than an accident, so it is stated here.
  def retry_policy = entry ? DO_NOT_AUTO_RETRY : AUTO_RETRY_UNDEFINED

  # True when the refusal follows the person, not the configuration: nothing an operator changes about the message
  # or the installation makes Meta accept it, so re-sending it is refused rather than offered.
  def recipient_scoped? = entry.present? && entry[:scope] == :recipient

  # What the dashboard needs in order to explain the refusal in the agent's own language and to decide whether
  # offering Retry would be honest. `retry_policy` is deliberately left out: it is about the background job, and a
  # UI reading it would confuse "Lynomia never re-sends this by itself" with "a person may not try again" -- which
  # for 131042 is exactly wrong, because an operator can fix the billing and the same message will then send.
  #
  # Nothing is reported for an unclassified code. The refusal itself is already on the message and the dashboard
  # already shows it; naming a classification for a code this installation has never seen would be inventing the
  # meaning this class exists to avoid inventing.
  def push_event_data
    return unless classified?

    { code: code, classification: classification, recipient_scoped: recipient_scoped? }
  end

  private

  def entry = CODES[@code]
end
