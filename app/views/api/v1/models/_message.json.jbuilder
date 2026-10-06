json.id message.id
json.content message.content
json.inbox_id message.inbox_id
json.echo_id message.echo_id if message.echo_id
json.conversation_id message.conversation.display_id
json.message_type message.message_type_before_type_cast
json.content_type message.content_type
json.status message.status
json.content_attributes message.content_attributes
json.created_at message.created_at.to_i
json.private message.private
json.source_id message.source_id
json.sender message.sender.push_event_data if message.sender
json.attachments message.attachments.map(&:push_event_data) if message.attachments.present?

json.set! :call, message.call.push_event_data if message.content_type == 'voice_call' && message.respond_to?(:call) && message.call.present?

# What Meta's refusal means, when it is one Lynomia classifies (custom/app/models/custom/message.rb). Derived, never
# stored, so the failures already on record carry it too; absent for everything else, which is most messages.
delivery_failure = message.delivery_failure_data if message.respond_to?(:delivery_failure_data)
json.set! :delivery_failure, delivery_failure if delivery_failure
