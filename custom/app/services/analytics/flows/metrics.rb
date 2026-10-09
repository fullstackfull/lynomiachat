# Lynomia Analytics: flow session lifecycle (docs/p8/02c-automation-flow-analytics.md).
#
# `flow_sessions` records where a conversation is in a flow and how its run ended. It is a CURRENT-state row with
# two timestamps -- created_at and finished_at -- and a steps_count. What it is not:
#
#   * There is NO per-node execution history. `current_node_id` holds only where the session is or stopped, and
#     nothing records the path it took. So there are no node-level metrics here: no per-node entry counts, no
#     drop-off-by-node, no path analysis. Those would have to be inferred from messages, which is not a record.
#
#   * There is NO "abandoned" state. A session that stops getting replies stays `waiting` until something ends
#     it -- the conversation resolving, the flow being disabled -- at which point it is `cancelled` with that
#     reason. Calling a long-waiting session "abandoned" would invent a state the product does not have, and the
#     threshold would be invented too. `waiting` sessions are reported as live, which is what they are.
#
# A session's duration is finished_at - created_at, which is wall-clock elapsed and includes every stretch the
# flow spent waiting for the customer. That is the honest reading of these two columns.
class Analytics::Flows::Metrics
  TERMINAL_STATUSES = %i[completed failed cancelled handed_off].freeze

  COUNT_METRICS = %i[sessions_started sessions_completed sessions_failed sessions_cancelled handed_off].freeze
  RATE_METRICS = %i[completion_rate].freeze
  DURATION_METRICS = %i[average_duration].freeze
  CURRENT_STATE_METRICS = %i[live_now].freeze
  EVENT_METRICS = (COUNT_METRICS + RATE_METRICS + DURATION_METRICS + %i[average_steps]).freeze
  ALL_METRICS = (EVENT_METRICS + CURRENT_STATE_METRICS).freeze

  STARTED_COLUMN = 'flow_sessions.created_at'.freeze
  FINISHED_COLUMN = 'flow_sessions.finished_at'.freeze
  DURATION_SECONDS = 'EXTRACT(EPOCH FROM (flow_sessions.finished_at - flow_sessions.created_at))'.freeze
  END_REASON = "flow_sessions.context ->> 'end_reason'".freeze

  def initialize(account:, date_range:, filters:)
    @account = account
    @date_range = date_range
    @filters = filters
  end

  def sessions_started
    started_in_range.count
  end

  def sessions_completed
    @sessions_completed ||= finished_in_range.where(status: :completed).count
  end

  def sessions_failed
    finished_in_range.where(status: :failed).count
  end

  def sessions_cancelled
    finished_in_range.where(status: :cancelled).count
  end

  def handed_off
    finished_in_range.where(status: :handed_off).count
  end

  # Of the sessions that ended in this period, the share that reached an End node. nil rather than 0 when none
  # ended, so "no run finished" does not read as "every run failed".
  def completion_rate
    total = finished_in_range.count
    return nil if total.zero?

    (sessions_completed.to_f / total * 100).round(1)
  end

  # Wall-clock seconds from start to end, averaged over the sessions that ended in this period. nil when none
  # did.
  def average_duration
    finished_in_range.average(Arel.sql(DURATION_SECONDS))&.to_f&.round
  end

  def average_steps
    finished_in_range.average(:steps_count)&.to_f&.round(1)
  end

  # Current state: sessions a customer could still answer right now. Not date filtered.
  def live_now
    all_sessions.live.count
  end

  def series(metric)
    counts = case metric
             when :sessions_started then bucketed(started_in_range, STARTED_COLUMN)
             when :sessions_completed then bucketed(finished_in_range.where(status: :completed), FINISHED_COLUMN)
             when :sessions_failed then bucketed(finished_in_range.where(status: :failed), FINISHED_COLUMN)
             end
    fill_buckets(counts)
  end

  def breakdown(dimension)
    case dimension
    when :bot then bot_rows
    when :status then status_rows
    when :failure then failure_rows
    when :end_reason then end_reason_rows
    end
  end

  private

  def all_sessions
    scope = FlowSession.where(account_id: @account.id)
    scope = scope.joins(:conversation).where(conversations: { inbox_id: @filters[:inbox_id] }) if @filters[:inbox_id]
    scope
  end

  def started_in_range
    all_sessions.where(created_at: @date_range.utc_range)
  end

  # finished_at is written for every terminal status by Flows::SessionEnd#close, so filtering on it selects the
  # runs that ENDED in this period -- a different and more useful set than the runs that started in it.
  def finished_in_range
    all_sessions.where(status: TERMINAL_STATUSES).where(finished_at: @date_range.utc_range)
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

  def bot_rows
    labels = @account.agent_bots.pluck(:id, :name).to_h
    finished_in_range.group(:agent_bot_id).count.sort_by { |_id, count| -count }
                     .map { |id, count| { id: id, label: labels[id] || "##{id}", value: count } }
  end

  def status_rows
    finished_in_range.group(:status).count.sort_by { |_status, count| -count }
                     .map { |status, count| { id: status, label: status, value: count } }
  end

  def failure_rows
    finished_in_range.where(status: :failed).group(:failure_code).count
                     .sort_by { |_code, count| -count }
                     .map { |code, count| { id: code.presence, label: code.presence, value: count } }
  end

  # Why a cancelled or handed-off run ended, as Flows::SessionEnd wrote it into context. `context` is plain jsonb
  # with no ActiveRecord::Store declaration, so it is read directly.
  def end_reason_rows
    finished_in_range.where(status: %i[cancelled handed_off]).group(Arel.sql(END_REASON)).count
                     .sort_by { |_reason, count| -count }
                     .map { |reason, count| { id: reason.presence, label: reason.presence, value: count } }
  end
end
