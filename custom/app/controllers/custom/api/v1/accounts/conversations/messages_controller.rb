# B13 -- a message is removed (docs/p-final/clean-room/specs/B-audit-event-capture.md).
#
# Recorded from the controller rather than from the model, because a message deletion is the one capture point
# that must record LESS than the record holds. The entry says which conversation the message was in, by the
# number a person recognises, and which inbox and sender it belonged to. The body and the attachments are
# deliberately absent -- not masked later by the read surface, but never written. That is the whole reason
# package A's renderer needs no special case for this one type (package B §5).
#
# The row lock is what makes a double deletion record once. Two agents can press delete on the same message at
# the same moment; upstream's destroy is idempotent and would simply rewrite the placeholder, so without the
# lock both requests would see an undeleted message and both would record. Holding it across the state change
# makes the second request read the first one's result.
module Custom::Api::V1::Accounts::Conversations::MessagesController
  AUDIT_EVENT = 'message.deleted'.freeze

  def destroy
    newly_deleted = false

    message.with_lock do
      newly_deleted = message.content_attributes['deleted'].blank?
      super
    end

    record_message_deletion if newly_deleted
  end

  private

  def record_message_deletion
    AuditTrail::Event.record_removal(
      auditable_type: 'Message', auditable_id: message.id, account: Current.account, comment: AUDIT_EVENT,
      changes: {
        # `display_id` is the key the browser reads to name the conversation
        # (app/javascript/dashboard/helper/auditlogHelper.js:186-189).
        display_id: @conversation.display_id,
        conversation_id: @conversation.id,
        inbox_id: @conversation.inbox_id,
        sender_type: message.sender_type,
        sender_id: message.sender_id
      }
    )
  end
end
