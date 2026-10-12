# Flow runs that ended on one of this contact's conversations.
#
# Ended, not started: a run's outcome is the thing worth a timeline row, and `finished_at` is written for every
# terminal status by Flows::SessionEnd#close. A live run has no outcome yet and is visible on the conversation
# itself.
#
# There is no node-level history in the schema, so a run contributes one row and not a step-by-step trace
# (docs/p8/02c-automation-flow-analytics.md).
class Contacts::ActivityTimeline::FlowsAdapter < Contacts::ActivityTimeline::BaseAdapter
  CATEGORY = 'conversations'.freeze
  TERMINAL_STATUSES = %i[completed failed cancelled handed_off].freeze

  def fetch(limit)
    rows(limit).map { |session| entry_for(session) }
  end

  private

  def rows(limit)
    scope = FlowSession.where(account_id: @account.id, conversation_id: conversation_ids,
                              status: TERMINAL_STATUSES)
                       .where.not(finished_at: nil)
                       .includes(:agent_bot)
                       .reorder(finished_at: :desc, id: :desc)
                       .limit(limit)
    cursor_scope(scope, :finished_at)
  end

  def entry_for(session)
    Contacts::ActivityTimeline::Entry.new(
      source: source, record_id: session.id, category: CATEGORY,
      kind: "flow_#{session.status}", occurred_at: session.finished_at,
      conversation_id: session.conversation_id,
      meta: {
        flow_id: session.agent_bot_id,
        flow_name: session.agent_bot&.name,
        steps: session.steps_count,
        failure_code: session.failure_code,
        end_reason: session.context['end_reason'],
        started_at: session.created_at.utc.iso8601
      }
    )
  end
end
