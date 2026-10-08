# Lynomia keeps Chatwoot's audit row for a deleted message after the Enterprise overlay goes, through the
# `prepend_mod_with` the OSS controller already declares
# (app/controllers/api/v1/accounts/conversations/messages_controller.rb:132).
#
# The deletion itself stays the OSS controller's: `super` is the only thing that touches the message, so the soft
# delete, its transaction and its authorization are untouched. This adds the audit row and nothing else.
#
# The reader was already waiting for these rows, which is what makes this the missing half of a finished feature
# rather than a new one: the serializer special-cases `auditable_type == 'Message'` to skip `push_event_data` and to
# drop `content` from the rendered payload (custom/app/views/api/v1/accounts/audit_logs/show.json.jbuilder), the
# dashboard has `message:destroy` -> `AUDIT_LOGS.MESSAGE.DELETE` and reads `display_id` out of `audited_changes` to
# name the conversation (app/javascript/dashboard/helper/auditlogHelper.js), and `Message` is already a filterable
# event type under CONVERSATIONS. Hence the payload keys below are a contract, not a choice.
module Custom::Api::V1::Accounts::Conversations::MessagesController
  def destroy
    audited_message = message

    # Lock before the deleted check so concurrent deletes cannot both write an audit entry.
    audited_message.with_lock do
      next super if audited_message.deleted

      audit_context = message_deletion_audit_context(audited_message)
      super
      create_message_deletion_audit_log(audited_message, audit_context)
    end
  end

  private

  # Snapshot the context before super soft-deletes the message.
  def message_deletion_audit_context(deleted_message)
    {
      'content' => deleted_message.content,
      'conversation_id' => deleted_message.conversation_id,
      'display_id' => deleted_message.conversation.display_id,
      'inbox_id' => deleted_message.inbox_id,
      'sender_type' => deleted_message.sender_type,
      'sender_id' => deleted_message.sender_id
    }
  end

  def create_message_deletion_audit_log(deleted_message, audit_context)
    Custom::AuditLog.create!(
      auditable: deleted_message,
      action: 'destroy',
      user: Current.user,
      associated: deleted_message.account,
      remote_address: request.remote_ip,
      audited_changes: audit_context
    )
  end
end
