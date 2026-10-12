# Assembles the automation execution response (docs/p8/02c-automation-flow-analytics.md).
class Analytics::Automations::Overview
  BREAKDOWN_DIMENSIONS = %i[rule skip_reason status].freeze
  DEFAULT_BREAKDOWN = :rule
  SERIES_METRICS = %i[episodes_armed executed skipped].freeze
  PERCENT_METRICS = Analytics::Automations::Metrics::RATE_METRICS

  def initialize(account:, date_range:, filters:, breakdown_by: nil)
    @account = account
    @date_range = date_range
    @filters = filters
    @breakdown_by = Analytics::Breakdown.resolve(breakdown_by, BREAKDOWN_DIMENSIONS, DEFAULT_BREAKDOWN)
    @metrics = Analytics::Automations::Metrics.new(account: account, date_range: date_range, filters: filters)
  end

  def call
    result = Analytics::Result.new(family: :automations, date_range: @date_range, filters: @filters,
                                   source: :raw, source_reason: :no_rollup_metric)

    add_warnings(result)
    Analytics::Automations::Metrics::COUNT_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric)) }
    PERCENT_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric), unit: :percent) }
    Analytics::Automations::Metrics::CURRENT_STATE_METRICS.each do |metric|
      result.add_kpi(metric, @metrics.public_send(metric), kind: :current_state)
    end

    SERIES_METRICS.each { |metric| result.add_series(metric, @metrics.series(metric)) }
    result.add_breakdown(:"by_#{@breakdown_by}", @breakdown_by, @metrics.breakdown(@breakdown_by))
    result
  end

  private

  # What this screen cannot report, stated in the response rather than left for a reader to assume away. Both
  # are properties of how the product records automations, not failures of this request.
  def add_warnings(result)
    result.degrade(:immediate_rules, :no_execution_record) if @metrics.immediate_rule_count.positive?
    result.degrade(:retention_window, :terminal_rows_purged_after_30_days) if @metrics.range_exceeds_retention?
  end
end
