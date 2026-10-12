# When did we first reply to the customer about this case? (docs/p9/03-sla-workflow.md)
#
# Computed from the messages that already exist, with NO new instrumentation and no hook on the message path:
# the first outgoing, non-private message in the linked conversation AT OR AFTER the case was opened. The
# conversation's own `first_reply_created_at` is deliberately not reused, because it records the first reply in
# the whole thread, which may be weeks before the case was raised.
#
# A case with no conversation has no first response to detect. That is a real product limitation, not a gap to
# fill with a guess: there is no channel on which a reply could have been sent.
class Support::Tickets::FirstResponseDetector
  def initialize(ticket)
    @ticket = ticket
  end

  def detect
    return nil if @ticket.conversation_id.blank?

    Message.where(conversation_id: @ticket.conversation_id, message_type: :outgoing, private: false)
           .where(created_at: @ticket.created_at..)
           .order(:created_at)
           .limit(1)
           .pick(:created_at)
  end
end
