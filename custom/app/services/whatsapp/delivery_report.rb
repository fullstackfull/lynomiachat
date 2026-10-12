# One of Meta's delivery reports, routed to the record that owns the message it is about
# (docs/p-final/clean-room/specs/E-whatsapp-delivery-status-propagation.md).
#
# This is a router and nothing more. It makes exactly two decisions -- which record owns the identifier, and
# "nothing owns it, so stop" -- and hands the outcome to that record's own advance rule. The forward-only
# ladder, the idempotency and the row lock all live on CampaignRecipient, where package D has to keep them
# anyway; a second copy here would be a second chance to disagree.
#
# A conversation message is not this class's business. Upstream handles those in full, with its own lock and its
# own forward-only rule in Messages::StatusUpdateService, and an identifier belongs to at most one of the two
# because a campaign send creates no message.
#
# **The lookup is scoped to the inbox the webhook was routed to.** The identifier in a report is
# attacker-supplied input on a public endpoint. Meta's signature is verified long before this runs and is the
# real protection, but the scope costs nothing -- the inbox is already resolved -- and it means a report
# delivered for one account cannot advance another account's record even if the signature check were ever to be
# got round.
class Whatsapp::DeliveryReport
  # The four states Meta reports. Anything else is ignored rather than stored: an unknown state on the record
  # would be a state no reader of it knows how to interpret.
  REPORTED_STATES = %w[sent delivered read failed].freeze

  # The entry arrives from the webhook payload, which reaches this point with indifferent access, and is
  # normalised once here so that every read below is spelled one way. A router whose correctness depends on
  # which flavour of hash its caller happened to build is a router that breaks the first time it is reused.
  def initialize(inbox:, entry:)
    @inbox = inbox
    @entry = (entry || {}).with_indifferent_access
  end

  # True when the report advanced a record, false when nothing owned the identifier or the state was not one
  # Lynomia records. A report that matches nothing is a normal event, not an error: Meta sends reports for
  # messages sent from other systems on the same number, for messages that predate this installation, and for
  # messages whose records have been deleted.
  def apply
    return false unless REPORTED_STATES.include?(state)

    recipient = campaign_recipient
    return false if recipient.blank?

    recipient.record_outcome!(
      state, reported_at: reported_at,
             error_code: failure['code'], error_title: failure['title'],
             error_message: failure.dig('error_data', 'details') || failure['message'] || failure['title']
    )
  end

  private

  def state
    @entry[:status].to_s
  end

  def source_id
    @entry[:id].presence
  end

  def campaign_recipient
    return nil if source_id.blank?

    CampaignRecipient.find_by(inbox_id: @inbox.id, source_id: source_id)
  end

  # Meta's own timestamp for the event, in unix seconds. A report without one is still a report, so the record
  # stamps it with the time it was applied.
  def reported_at
    seconds = Integer(@entry[:timestamp].to_s, exception: false)
    seconds&.positive? ? Time.zone.at(seconds) : nil
  end

  # A `failed` report carries an `errors` array; every other state carries none. `title` is the human part here,
  # which is the opposite of a send response, where `message` is -- so the two shapes are read where each is
  # read rather than through one guess about both.
  def failure
    @failure ||= Array(@entry[:errors]).first || {}
  end
end
