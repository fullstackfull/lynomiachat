# The measured moments in this contact's conversations: first response, resolution, bot handoff, bot resolution
# and each reopen.
#
# `reply_time` is deliberately excluded: it is written once per agent reply, so including it would bury every
# other event under a row per message and tell the reader nothing a message row does not.
#
# A `conversation_opened` row is a reopen only when its `event_start_time` differs from the conversation's
# `created_at` -- the discriminator the listener itself establishes
# (app/listeners/reporting_event_listener.rb:101-124). A first open is dropped here because
# ConversationEventsAdapter already reports the conversation's creation.
class Contacts::ActivityTimeline::ReportingEventsAdapter < Contacts::ActivityTimeline::BaseAdapter
  CATEGORY = 'conversations'.freeze

  NAMES = %w[first_response conversation_resolved conversation_bot_handoff conversation_bot_resolved conversation_opened].freeze

  KINDS = {
    'first_response' => 'first_response',
    'conversation_resolved' => 'conversation_resolved',
    'conversation_bot_handoff' => 'bot_handoff',
    'conversation_bot_resolved' => 'bot_resolved',
    'conversation_opened' => 'conversation_reopened'
  }.freeze

  # Durations only mean something for the two metrics that measure one.
  DURATION_NAMES = %w[first_response conversation_resolved].freeze

  def fetch(limit)
    rows(limit).map { |event| entry_for(event) }
  end

  private

  def rows(limit)
    scope = ReportingEvent.where(account_id: @account.id, name: NAMES, conversation_id: conversation_ids)
                          .joins(:conversation)
                          .where("reporting_events.name <> 'conversation_opened' " \
                                 'OR reporting_events.event_start_time <> conversations.created_at')
                          .reorder('reporting_events.created_at DESC, reporting_events.id DESC')
                          .limit(limit)
    cursor_scope(scope, :created_at)
  end

  def entry_for(event)
    Contacts::ActivityTimeline::Entry.new(
      source: source, record_id: event.id, category: CATEGORY,
      kind: KINDS.fetch(event.name), occurred_at: event.created_at,
      conversation_id: event.conversation_id,
      meta: {
        duration_seconds: DURATION_NAMES.include?(event.name) ? event.value&.to_i : nil,
        agent_id: event.user_id,
        inbox_id: event.inbox_id
      }
    )
  end
end
