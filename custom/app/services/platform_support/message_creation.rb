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
# `last_operator_message_at`, which is half of the derived unread flag, and stamps `first_responded_at` the
# first time -- the plain fact of when Lynomia first answered, recorded where the answer is written rather than
# inferred later by a sweep. The SLA engine owns everything derived from that fact: the met/breach events, the
# due times, and recomputing the resolution clock after the reopen below.
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
      reopen_if_resolved
      stamp_ticket(message)
      record_reply(message)
      audit(message)
    end

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
  # `resolution_breached_at` is cleared because a reopened ticket is not a ticket that breached and finished;
  # the fresh due time is the SLA engine's to compute, since the calendar arithmetic and the pause accounting
  # live there and a second implementation of them here would be a second answer.
  def reopen_if_resolved
    return unless @ticket.resolved? && customer_reply?

    @ticket.assign_attributes(status: :open, resolved_at: nil, closed_at: nil, resolution_breached_at: nil)
    PlatformSupport::EventRecorder.new(ticket: @ticket, actor: @author).record(
      'reopened', metadata: { from: 'resolved', to: 'open' }
    )
  end

  def stamp_ticket(message)
    if customer_reply?
      @ticket.last_customer_message_at = message.created_at
    else
      @ticket.last_operator_message_at = message.created_at
      @ticket.first_responded_at ||= message.created_at
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

  # Staff replies only: the audit trail is Lynomia's record of what its own staff did. A customer's own reply is
  # already in the thread they can read, and filing it here would add a row no reader asked for.
  def audit(message)
    return unless @author.is_a?(PlatformSupport::Agent)

    PlatformSupport::AuditWriter.new(actor: @author.user).write(
      @ticket, 'operator_replied', { 'message_id' => message.id, 'agent_id' => @author.id }
    )
  end
end
