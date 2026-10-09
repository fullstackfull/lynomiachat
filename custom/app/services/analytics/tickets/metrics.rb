# Support-case metrics (docs/p9/02-support-tickets.md §analytics).
#
# Deliberately small. The brief's rule for this phase is minimal ticket analytics on P8's existing architecture,
# not a second analytics phase, so this family answers the five questions a support lead actually asks -- how
# much arrived, how much closed, how much came back, how fast we close, and how often we missed a target -- plus
# three readings of how things stand now.
#
# WHAT IS NOT HERE, and why:
#   * No SLA attainment percentage. Every SLA figure in this product begins when a policy is first attached to a
#     case (docs/p9/03-sla-workflow.md), so a percentage over a range that predates the policy would be a ratio
#     of two different populations. The breach COUNTS are honest; the rate is not.
#   * No first-response time average. `first_responded_at` is filled by a sweep over cases that have a policy,
#     so averaging it would describe the governed subset while looking like it described all cases.
#   * No reopen rate for the same reason as the breach rate: the denominator moves.
class Analytics::Tickets::Metrics
  COUNT_METRICS = %i[tickets_created tickets_resolved tickets_reopened first_response_breaches
                     resolution_breaches].freeze
  DURATION_METRICS = %i[average_resolution_time].freeze
  CURRENT_STATE_METRICS = %i[open_now overdue_now unassigned_now].freeze
  EVENT_METRICS = (COUNT_METRICS + DURATION_METRICS).freeze
  ALL_METRICS = (EVENT_METRICS + CURRENT_STATE_METRICS).freeze

  RESOLUTION_SECONDS = 'EXTRACT(EPOCH FROM (support_tickets.resolved_at - support_tickets.created_at))'.freeze
  REOPENED_EVENT = 'reopened'.freeze

  def initialize(account:, date_range:, filters:)
    @account = account
    @date_range = date_range
    @filters = filters
  end

  def tickets_created
    tickets.where(created_at: @date_range.utc_range).count
  end

  def tickets_resolved
    resolved_in_range.count
  end

  # From the durable event trail, not inferred from the current status: a case reopened and resolved again would
  # otherwise be invisible.
  def tickets_reopened
    Support::TicketEvent.where(account_id: @account.id, event_type: REOPENED_EVENT,
                               created_at: @date_range.utc_range)
                        .where(support_ticket_id: tickets.select(:id))
                        .count
  end

  def first_response_breaches
    tickets.where(first_response_breached_at: @date_range.utc_range).count
  end

  def resolution_breaches
    tickets.where(resolution_breached_at: @date_range.utc_range).count
  end

  # nil, never zero, when nothing was resolved: a zero would read as "we close instantly".
  def average_resolution_time
    average = resolved_in_range.average(Arel.sql(RESOLUTION_SECONDS))
    average&.to_f&.round
  end

  # Current state, not a count over the range.
  def open_now
    tickets.active.count
  end

  def overdue_now
    tickets.overdue.count
  end

  def unassigned_now
    tickets.active.unassigned.count
  end

  # Not a KPI: the condition under which the breach counts describe only part of the picture. A case with no
  # policy can never breach, so when some are ungoverned a zero breach count does not mean nothing was late.
  def ungoverned_active_count
    tickets.active.where(sla_policy_id: nil).count
  end

  def series(metric)
    counts = case metric
             when :tickets_created then bucketed(tickets.where(created_at: @date_range.utc_range), 'support_tickets.created_at')
             when :tickets_resolved then bucketed(resolved_in_range, 'support_tickets.resolved_at')
             when :resolution_breaches
               bucketed(tickets.where(resolution_breached_at: @date_range.utc_range),
                        'support_tickets.resolution_breached_at')
             end
    fill_buckets(counts)
  end

  def breakdown(dimension)
    case dimension
    when :priority then enum_rows(:priority)
    when :status then enum_rows(:status)
    when :category then created_in_range.group(:category).count.then { |counts| labelled(counts) }
    when :team then rows_for(created_in_range.where.not(team_id: nil).group(:team_id), team_labels)
    when :assignee then rows_for(created_in_range.where.not(assignee_id: nil).group(:assignee_id), agent_labels)
    end
  end

  private

  # Account scope first, then the shared filters. Every filter id was already proved to belong to this account by
  # Analytics::FilterSet before it reached here.
  def tickets
    scope = @account.support_tickets
    scope = scope.where(inbox_id: @filters[:inbox_id]) if @filters[:inbox_id]
    scope = scope.where(team_id: @filters[:team_id]) if @filters[:team_id]
    scope = scope.where(assignee_id: @filters[:agent_id]) if @filters[:agent_id]
    scope
  end

  def created_in_range
    tickets.where(created_at: @date_range.utc_range)
  end

  def resolved_in_range
    tickets.where(resolved_at: @date_range.utc_range)
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

  def enum_rows(column)
    labelled(created_in_range.group(column).count)
  end

  def labelled(counts)
    counts.sort_by { |_value, count| -count }
          .map { |value, count| { id: value, label: value, value: count } }
  end

  def rows_for(grouped, labels)
    grouped.count.sort_by { |_id, count| -count }
           .map { |id, count| { id: id, label: labels[id] || "##{id}", value: count } }
  end

  def team_labels
    @team_labels ||= @account.teams.pluck(:id, :name).to_h
  end

  def agent_labels
    @agent_labels ||= @account.users.pluck(:id, :name).to_h
  end
end
