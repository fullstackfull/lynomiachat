# Assembles the flow session response (docs/p8/02c-automation-flow-analytics.md).
class Analytics::Flows::Overview
  BREAKDOWN_DIMENSIONS = %i[bot status failure end_reason].freeze
  DEFAULT_BREAKDOWN = :bot
  SERIES_METRICS = %i[sessions_started sessions_completed sessions_failed].freeze

  def initialize(account:, date_range:, filters:, breakdown_by: nil)
    @account = account
    @date_range = date_range
    @filters = filters
    @breakdown_by = Analytics::Breakdown.resolve(breakdown_by, BREAKDOWN_DIMENSIONS, DEFAULT_BREAKDOWN)
    @metrics = Analytics::Flows::Metrics.new(account: account, date_range: date_range, filters: filters)
  end

  def call
    result = Analytics::Result.new(family: :flows, date_range: @date_range, filters: @filters,
                                   source: :raw, source_reason: :no_rollup_metric)

    Analytics::Flows::Metrics::COUNT_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric)) }
    Analytics::Flows::Metrics::RATE_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric), unit: :percent) }
    Analytics::Flows::Metrics::DURATION_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric), unit: :seconds) }
    result.add_kpi(:average_steps, @metrics.average_steps)
    Analytics::Flows::Metrics::CURRENT_STATE_METRICS.each do |metric|
      result.add_kpi(metric, @metrics.public_send(metric), kind: :current_state)
    end

    SERIES_METRICS.each { |metric| result.add_series(metric, @metrics.series(metric)) }
    result.add_breakdown(:"by_#{@breakdown_by}", @breakdown_by, @metrics.breakdown(@breakdown_by))
    result
  end
end
