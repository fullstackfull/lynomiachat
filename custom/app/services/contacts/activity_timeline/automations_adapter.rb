# Delayed automation episodes that reached an outcome on one of this contact's conversations.
#
# Only delayed rules leave a record at all, and only within the 30-day retention window
# (docs/p8/02c-automation-flow-analytics.md). An immediate rule writes nothing anywhere, so it cannot appear
# here, and nothing infers one from a message it may have sent.
#
# Pending rows are excluded: an episode whose clock is still running has not happened yet, and a timeline is a
# record of what did.
class Contacts::ActivityTimeline::AutomationsAdapter < Contacts::ActivityTimeline::BaseAdapter
  CATEGORY = 'automations'.freeze
  TERMINAL_STATUSES = %i[executed skipped].freeze

  def fetch(limit)
    rows(limit).map { |execution| entry_for(execution) }
  end

  private

  # updated_at is when the episode reached its outcome, which is the moment this entry is about. created_at is
  # when its clock started, and is carried in meta.
  def rows(limit)
    scope = AutomationRulePendingExecution
            .where(account_id: @account.id, conversation_id: conversation_ids, status: TERMINAL_STATUSES)
            .includes(:automation_rule)
            .reorder(updated_at: :desc, id: :desc)
            .limit(limit)
    cursor_scope(scope, :updated_at)
  end

  def entry_for(execution)
    Contacts::ActivityTimeline::Entry.new(
      source: source, record_id: execution.id, category: CATEGORY,
      kind: "automation_#{execution.status}", occurred_at: execution.updated_at,
      conversation_id: execution.conversation_id,
      meta: {
        rule_id: execution.automation_rule_id,
        rule_name: execution.automation_rule&.name,
        skip_reason: execution.skip_reason,
        armed_at: execution.created_at.utc.iso8601
      }
    )
  end
end
