# What happened TO this contact's conversations: each conversation opening, and each activity message.
#
# Activity messages are the only history of an assignee, team, label, priority or status change
# (docs/p8/00-discovery.md §3): `conversations.status_changed_at` holds the most recent transition and
# `assignee_id` the current assignee, so neither is a history source.
#
# Only `conversation_status_changed` carries a structured `content_attributes.activity`; every other activity
# message is localized prose written at the time. Those are surfaced AS the recorded text, with
# `kind: 'conversation_activity'`, and nothing parses the prose to guess what it described. The response is
# therefore honest about which rows are structured and which are a sentence.
class Contacts::ActivityTimeline::ConversationEventsAdapter < Contacts::ActivityTimeline::BaseAdapter
  CATEGORY = 'conversations'.freeze
  STATUS_ACTIVITY = 'conversation_status_changed'.freeze

  def fetch(limit)
    (conversation_entries(limit) + activity_entries(limit)).sort_by(&:sort_key).first(limit)
  end

  private

  def conversation_entries(limit)
    cursor_scope(
      contact_conversations.reorder(created_at: :desc, id: :desc).limit(limit), :created_at
    ).map do |conversation|
      Contacts::ActivityTimeline::Entry.new(
        source: source, record_id: conversation.id, category: CATEGORY,
        kind: 'conversation_created', occurred_at: conversation.created_at,
        conversation_id: conversation.id,
        meta: { display_id: conversation.display_id, inbox_id: conversation.inbox_id, status: conversation.status }
      )
    end
  end

  # Activity rows share the messages table, so they share its id space and need their own source key to keep the
  # cursor's total order unambiguous -- hence `activity_message` rather than this adapter's own name.
  def activity_entries(limit)
    scope = Message.where(account_id: @account.id, conversation_id: conversation_ids, message_type: :activity)
                   .reorder(created_at: :desc, id: :desc)
                   .limit(limit)
    activity_cursor_scope(scope).map { |message| activity_entry(message) }
  end

  def activity_cursor_scope(scope)
    return scope if @cursor.nil?

    older = 'messages.created_at < :instant'
    case @cursor.source <=> 'activity_message'
    when -1 then scope.where("#{older} OR messages.created_at = :instant", instant: @cursor.occurred_at)
    when 0 then scope.where("#{older} OR (messages.created_at = :instant AND messages.id < :id)",
                            instant: @cursor.occurred_at, id: @cursor.record_id)
    else scope.where(older, instant: @cursor.occurred_at)
    end
  end

  def activity_entry(message)
    activity = message.content_attributes&.dig('activity') || {}
    structured = activity['type'] == STATUS_ACTIVITY

    Contacts::ActivityTimeline::Entry.new(
      source: 'activity_message', record_id: message.id, category: CATEGORY,
      kind: structured ? 'conversation_status_changed' : 'conversation_activity',
      occurred_at: message.created_at, conversation_id: message.conversation_id,
      summary: message.content,
      meta: { status: structured ? activity['status'] : nil, structured: structured }
    )
  end
end
