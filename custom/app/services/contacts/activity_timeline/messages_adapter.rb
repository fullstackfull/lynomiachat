# Messages this contact exchanged, across every conversation the caller may see.
#
# `messages` has no `contact_id` at all, so the only path is through `conversations.contact_id`
# (docs/p8/00-discovery.md §7). Activity rows are excluded here and read by ConversationEventsAdapter instead,
# so the two never produce the same row twice.
#
# Private notes ARE included, with their own kind, because that is what the conversation view does: anyone who
# can open the conversation sees its private notes, and the timeline is gated on the same conversation
# visibility. It introduces no new disclosure, and leaving them out would make the timeline disagree with the
# thread it summarises.
class Contacts::ActivityTimeline::MessagesAdapter < Contacts::ActivityTimeline::BaseAdapter
  CATEGORY = 'messages'.freeze

  KINDS = {
    'incoming' => 'message_incoming',
    'outgoing' => 'message_outgoing',
    'template' => 'message_system_template'
  }.freeze

  def fetch(limit)
    rows(limit).map { |message| entry_for(message) }
  end

  private

  def rows(limit)
    scope = Message.where(account_id: @account.id, conversation_id: conversation_ids)
                   .where.not(message_type: :activity)
                   .includes(:inbox)
                   .reorder(created_at: :desc, id: :desc)
                   .limit(limit)
    cursor_scope(scope, :created_at)
  end

  def entry_for(message)
    Contacts::ActivityTimeline::Entry.new(
      source: source, record_id: message.id, category: CATEGORY,
      kind: kind_for(message), occurred_at: message.created_at,
      conversation_id: message.conversation_id, summary: message.content,
      meta: {
        inbox_id: message.inbox_id,
        channel: message.inbox&.channel_type,
        status: message.status,
        template_name: message.additional_attributes&.dig('template_params', 'name')
      }
    )
  end

  def kind_for(message)
    return 'private_note' if message.private?

    KINDS.fetch(message.message_type, 'message_outgoing')
  end
end
