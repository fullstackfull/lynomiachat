# Adds one reply to a Platform Support ticket's public thread
# (docs/platform-support/12-refresh-against-product-refinement.md §2 "POST /tickets/:id/messages", §4).
#
# THE ONLY WRITER OF A REPLY, from either side. The tenant endpoint and the staff reply form both arrive here,
# which is why the rules that must hold for every reply live here and not in two controllers:
#
#   closed      refused with 422. The customer opens a new ticket, which is what the message says, because a
#               closed thread that silently accepts a reply is a thread nobody is reading.
#   resolved    a CUSTOMER reply succeeds and REOPENS the ticket. "Resolved" is Lynomia's claim, and the
#               customer saying it is not fixed is the one thing that must never be swallowed.
#   open-ish    nothing special; the reply lands.
#
# WHAT A REPLY STAMPS. A customer reply moves `last_customer_message_at`; an operator reply moves
# `last_operator_message_at`, which is half of the derived unread flag, and asks `Sla::Clock` to stamp
# `first_responded_at` the first time -- the plain fact of when Lynomia first answered, decided where the
# answer is written rather than inferred later by a sweep. Every date calculation behind that fact belongs to
# the clock, including the new resolution target after the reopen below; this service decides WHEN to ask.
#
# WHAT A REPLY SETS IN MOTION, once the transaction has committed: the first-response outcome event, the one
# notification row type this module writes (operator replies only, §5) and one email to the other side. Both
# happen after the commit because a worker can pick up a job before the transaction that enqueued it commits.
class PlatformSupport::MessageCreation
  def initialize(ticket:, author:, body:, blobs: [])
    @ticket = ticket
    @author = author
    @body = body
    @blobs = blobs
  end

  def perform
    raise CustomExceptions::PlatformTickets::TicketClosed.new({}) if @ticket.closed?

    message = nil
    ActiveRecord::Base.transaction do
      message = write_message
      reopen_if_resolved(message)
      stamp_ticket(message)
      record_reply(message)
      record_first_response_outcome
      audit(message)
    end

    announce(message)
    message
  end

  private

  def write_message
    message = @ticket.messages.create!(author_attributes.merge(body: @body))
    message.platform_support_message_files.attach(@blobs) if @blobs.present?
    message
  end

  def author_attributes
    @author_attributes ||= PlatformSupport::Message.author_attributes_for(@author)
  end

  def customer_reply?
    author_attributes[:author_type] == PlatformSupport::Message::CUSTOMER_AUTHOR_TYPE
  end

  # Only a customer reopens by replying. An operator replying to a ticket they have already resolved is
  # finishing a thought, not reopening the work.
  #
  # The fresh resolution target, and the clearing of `resolution_breached_at`, are `Clock#restart_resolution`'s
  # to decide: a reopened ticket is not a ticket that breached and finished, and a second implementation of
  # that arithmetic here would be a second answer. Measured from the reply, which is the moment the ticket
  # became open work again.
  def reopen_if_resolved(message)
    return unless @ticket.resolved? && customer_reply?

    @ticket.assign_attributes(status: :open, resolved_at: nil, closed_at: nil)
    clock.restart_resolution(from: message.created_at)
    PlatformSupport::EventRecorder.new(ticket: @ticket, actor: @author).record(
      'reopened', metadata: { from: 'resolved', to: 'open' }
    )
  end

  # Whether THIS reply is the first response is read before the clock is asked, because the clock decides once
  # and never again: afterwards `first_responded_at` is present either way and the outcome event below could no
  # longer tell a first reply from a tenth.
  def stamp_ticket(message)
    if customer_reply?
      @ticket.last_customer_message_at = message.created_at
    else
      @ticket.last_operator_message_at = message.created_at
      @decided_first_response = @ticket.first_responded_at.nil?
      clock.record_first_response(at: message.created_at)
    end
    @ticket.last_activity_at = message.created_at
    @ticket.save!
  end

  def record_reply(message)
    PlatformSupport::EventRecorder.new(ticket: @ticket, actor: @author).record(
      customer_reply? ? 'customer_replied' : 'operator_replied',
      metadata: { message_id: message.id, attachments: message.platform_support_message_files.count }
    )
  end

  # THE OUTCOME EVENT IS WRITTEN BY WHOEVER DECIDED THE OUTCOME, which for a first response is this reply --
  # the clock stamps the fact and `Sla::Sweeper` only ever decides a breach against the desk, never a met.
  # A ticket with no first-response target promised nothing, so there is no outcome to record: a `met` event
  # against no promise would read as a target that existed and was hit.
  def record_first_response_outcome
    return unless @decided_first_response
    return if @ticket.first_response_due_at.nil?

    breached = @ticket.first_response_breached_at.present?
    PlatformSupport::EventRecorder.new(ticket: @ticket).record(
      breached ? 'sla_first_response_breached' : 'sla_first_response_met',
      metadata: { due_at: @ticket.first_response_due_at.iso8601,
                  responded_at: @ticket.first_responded_at.iso8601 }
    )
  end

  # Staff replies only: the audit trail is Lynomia's record of what its own staff did. A customer's own reply is
  # already in the thread they can read, and filing it here would add a row no reader asked for.
  def audit(message)
    return unless @author.is_a?(PlatformSupport::Agent)

    PlatformSupport::AuditWriter.new(actor: @author.user).write(
      @ticket, 'operator_replied', { 'message_id' => message.id, 'agent_id' => @author.id }
    )
  end

  # THE TWO AUDIENCES, told by different means and never the same means. The customer gets the bell row -- the
  # only `platform_support_reply` notification this module writes, and only for an operator reply -- plus the
  # one email that matters. The desk gets email only: a Lynomia operator has no tenant notification feed to
  # write to, which is the whole reason `PlatformSupport::Agent` exists rather than an AccountUser.
  #
  # The mailers refuse themselves when there is no address to send to, so nothing is pre-checked here and no
  # address is ever invented.
  def announce(message)
    if customer_reply?
      PlatformSupport::TicketMailer.customer_replied(@ticket, message).deliver_later
    else
      PlatformSupport::Notifications::ReplyNotifier.new(ticket: @ticket).perform
      PlatformSupport::TicketMailer.operator_replied(@ticket, message).deliver_later
    end
  end

  def clock
    @clock ||= PlatformSupport::Sla::Clock.new(@ticket)
  end
end
