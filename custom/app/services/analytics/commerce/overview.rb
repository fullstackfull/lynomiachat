# Assembles the commerce response (docs/p8/02d-commerce-analytics.md).
class Analytics::Commerce::Overview
  BREAKDOWN_DIMENSIONS = %i[provider store currency action_type action_error].freeze
  DEFAULT_BREAKDOWN = :provider
  SERIES_METRICS = %i[carts_abandoned carts_targeted carts_completed].freeze

  def initialize(account:, date_range:, filters:, breakdown_by: nil)
    @account = account
    @date_range = date_range
    @filters = filters
    @breakdown_by = Analytics::Breakdown.resolve(breakdown_by, BREAKDOWN_DIMENSIONS, DEFAULT_BREAKDOWN)
    @metrics = Analytics::Commerce::Metrics.new(account: account, date_range: date_range, filters: filters)
  end

  def call
    result = Analytics::Result.new(family: :commerce, date_range: @date_range, filters: @filters,
                                   source: :raw, source_reason: :no_rollup_metric)

    Analytics::Commerce::Metrics::COUNT_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric)) }
    Analytics::Commerce::Metrics::RATE_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric), unit: :percent) }
    Analytics::Commerce::Metrics::CURRENT_STATE_METRICS.each do |metric|
      result.add_kpi(metric, @metrics.public_send(metric), kind: :current_state)
    end

    SERIES_METRICS.each { |metric| result.add_series(metric, @metrics.series(metric)) }
    result.add_breakdown(:"by_#{@breakdown_by}", @breakdown_by, @metrics.breakdown(@breakdown_by))
    result
  end
end
