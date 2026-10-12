# Assembles the support-case analytics response (docs/p9/02-support-tickets.md §analytics).
#
# Raw throughout and labelled as such: `reporting_events_rollups` carries no ticket dimension, so there is no
# rollup row that could answer any of this and `source_reason` says exactly that rather than leaving a reader to
# wonder whether a rollup was skipped.
class Analytics::Tickets::Overview
  BREAKDOWN_DIMENSIONS = %i[priority category status team assignee].freeze
  DEFAULT_BREAKDOWN = :priority
  SERIES_METRICS = %i[tickets_created tickets_resolved resolution_breaches].freeze

  def initialize(account:, date_range:, filters:, breakdown_by: nil)
    @account = account
    @date_range = date_range
    @filters = filters
    @breakdown_by = Analytics::Breakdown.resolve(breakdown_by, BREAKDOWN_DIMENSIONS, DEFAULT_BREAKDOWN)
    @metrics = Analytics::Tickets::Metrics.new(account: account, date_range: date_range, filters: filters)
  end

  def call
    result = Analytics::Result.new(family: :tickets, date_range: @date_range, filters: @filters,
                                   source: :raw, source_reason: :no_rollup_metric)

    Analytics::Tickets::Metrics::COUNT_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric)) }
    Analytics::Tickets::Metrics::DURATION_METRICS.each do |metric|
      result.add_kpi(metric, @metrics.public_send(metric), unit: :seconds)
    end
    Analytics::Tickets::Metrics::CURRENT_STATE_METRICS.each do |metric|
      result.add_kpi(metric, @metrics.public_send(metric), kind: :current_state)
    end

    SERIES_METRICS.each { |metric| result.add_series(metric, @metrics.series(metric)) }
    result.add_breakdown(:"by_#{@breakdown_by}", @breakdown_by, @metrics.breakdown(@breakdown_by))
    warn_about_ungoverned_cases(result)
    result
  end

  private

  # A case with no SLA policy can never breach, so when some active cases are ungoverned a zero breach count does
  # not mean nothing was late. Conditional, not permanent: a warning that is always present is a banner an
  # operator learns to ignore, and the broader statement that every SLA figure begins when a policy is attached
  # lives in the family notes and the screen's footnote where it belongs.
  def warn_about_ungoverned_cases(result)
    return if @metrics.ungoverned_active_count.zero?

    result.degrade(:sla, :active_cases_without_a_policy)
  end
end
