# Lynomia Analytics: automation execution (docs/p8/02c-automation-flow-analytics.md).
#
# This family reports ONLY what the product durably records, which is a strict subset of what it does:
#
#   * A DELAYED rule (`automation_rules.execution_delay` present) arms a row in
#     `automation_rule_pending_executions` and that row carries its outcome. Those are the rows read here.
#
#   * An IMMEDIATE rule (no execution_delay) runs inline and writes nothing anywhere. There is no execution
#     record to count, so immediate rules are ABSENT from these numbers rather than reported as zero, and the
#     response says so through a warning instead of letting a reader assume the screen covers every rule.
#
#   * Terminal rows are purged after `AutomationRulePendingExecution::RETENTION_WINDOW` (30 days), so a range
#     reaching further back than that is incomplete by construction. The response warns rather than presenting a
#     truncated history as a complete one.
#
# Nothing here reconstructs an execution from a side effect. An automation that sent a message leaves a message,
# but attributing messages back to rules would be inference, not a record.
class Analytics::Automations::Metrics
  COUNT_METRICS = %i[episodes_armed executed skipped].freeze
  RATE_METRICS = %i[execution_rate].freeze
  CURRENT_STATE_METRICS = %i[awaiting_now stranded_now].freeze
  EVENT_METRICS = (COUNT_METRICS + RATE_METRICS).freeze
  ALL_METRICS = (EVENT_METRICS + CURRENT_STATE_METRICS).freeze

  # Terminal rows carry their outcome time in updated_at, which is also the column the retention sweep and the
  # (status, updated_at) index use. created_at is when the episode was armed, which is a different question and
  # is reported separately as `episodes_armed`.
  OUTCOME_COLUMN = 'automation_rule_pending_executions.updated_at'.freeze
  ARMED_COLUMN = 'automation_rule_pending_executions.created_at'.freeze

  def initialize(account:, date_range:, filters:)
    @account = account
    @date_range = date_range
    @filters = filters
  end

  def episodes_armed
    armed_in_range.count
  end

  def executed
    @executed ||= outcomes_in_range.where(status: :executed).count
  end

  def skipped
    @skipped ||= outcomes_in_range.where(status: :skipped).count
  end

  # Of the episodes that reached an outcome, the share that acted. nil rather than 0 when none did, so "nothing
  # was due" does not read as "everything was skipped".
  def execution_rate
    total = executed + skipped
    return nil if total.zero?

    (executed.to_f / total * 100).round(1)
  end

  # Current state: episodes still bound to fire. Not date filtered -- a queue is a reading taken now.
  def awaiting_now
    all_executions.armed.count
  end

  # Current state: rows whose worker died while the customer-facing actions were running. Nothing reclaims them
  # by design, because repeating a send is worse than dropping it (app/models/automation_rule_pending_execution.rb),
  # so they are surfaced here rather than left silent.
  def stranded_now
    all_executions.abandoned.count
  end

  def series(metric)
    counts = case metric
             when :episodes_armed then bucketed(armed_in_range, ARMED_COLUMN)
             when :executed then bucketed(outcomes_in_range.where(status: :executed), OUTCOME_COLUMN)
             when :skipped then bucketed(outcomes_in_range.where(status: :skipped), OUTCOME_COLUMN)
             end
    fill_buckets(counts)
  end

  def breakdown(dimension)
    case dimension
    when :rule then rule_rows
    when :skip_reason then skip_reason_rows
    when :status then status_rows
    end
  end

  # Rules this screen cannot speak for, because they leave no execution record at all.
  def immediate_rule_count
    @immediate_rule_count ||= @account.automation_rules.where(execution_delay: nil).count
  end

  # True when the requested range reaches past the retention window, so terminal rows in the older part have
  # already been purged.
  def range_exceeds_retention?
    @date_range.starts_at < AutomationRulePendingExecution::RETENTION_WINDOW.ago
  end

  private

  def all_executions
    scope = AutomationRulePendingExecution.where(account_id: @account.id)
    scope = scope.where(automation_rule_id: @filters[:automation_rule_id]) if @filters[:automation_rule_id]
    scope
  end

  def armed_in_range
    all_executions.where(created_at: @date_range.utc_range)
  end

  def outcomes_in_range
    all_executions.where(updated_at: @date_range.utc_range)
  end

  def bucketed(scope, column)
    scope.group_by_period(@date_range.group_by, Arel.sql(column),
                          time_zone: @date_range.zone, default_value: 0).count
  end

  def fill_buckets(counts)
    normalized = (counts || {}).transform_keys { |key| key.to_date.strftime(Analytics::DateRange::DATE_FORMAT) }
    @date_range.bucket_starts.map do |bucket|
      key = bucket.to_date.strftime(Analytics::DateRange::DATE_FORMAT)
      { bucket: key, value: normalized[key].to_i }
    end
  end

  def rule_rows
    labels = @account.automation_rules.pluck(:id, :name).to_h
    outcomes_in_range.group(:automation_rule_id).count.sort_by { |_id, count| -count }
                     .map { |id, count| { id: id, label: labels[id] || "##{id}", value: count } }
  end

  # The reason the rule declined to act at fire time, as the runner recorded it. A small fixed set of strings,
  # so grouping on it stays low cardinality and needs no mapping table.
  def skip_reason_rows
    outcomes_in_range.where(status: :skipped).group(:skip_reason).count
                     .sort_by { |_reason, count| -count }
                     .map { |reason, count| { id: reason.presence, label: reason.presence, value: count } }
  end

  def status_rows
    outcomes_in_range.group(:status).count.sort_by { |_status, count| -count }
                     .map { |status, count| { id: status, label: status, value: count } }
  end
end
