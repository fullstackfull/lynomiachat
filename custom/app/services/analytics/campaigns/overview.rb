# Assembles the campaign performance response (docs/p8/02b-whatsapp-campaign-analytics.md).
class Analytics::Campaigns::Overview
  BREAKDOWN_DIMENSIONS = %i[campaign audience failure skip_reason].freeze
  DEFAULT_BREAKDOWN = :campaign
  SERIES_METRICS = %i[recipients_targeted delivered failed].freeze
  RATE_METRICS = Analytics::Campaigns::Metrics::RATE_METRICS

  def initialize(account:, date_range:, filters:, breakdown_by: nil)
    @account = account
    @date_range = date_range
    @filters = filters
    @breakdown_by = Analytics::Breakdown.resolve(breakdown_by, BREAKDOWN_DIMENSIONS, DEFAULT_BREAKDOWN)
    @metrics = Analytics::Campaigns::Metrics.new(account: account, date_range: date_range, filters: filters)
  end

  def call
    # campaign_recipients has no rollup dimension; this family is raw by construction.
    result = Analytics::Result.new(family: :campaigns, date_range: @date_range, filters: @filters,
                                   source: :raw, source_reason: :no_rollup_metric)

    Analytics::Campaigns::Metrics::COUNT_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric)) }
    RATE_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric), unit: :percent) }

    SERIES_METRICS.each { |metric| result.add_series(metric, @metrics.series(metric)) }
    result.add_breakdown(:"by_#{@breakdown_by}", @breakdown_by, @metrics.breakdown(@breakdown_by))
    result
  end
end
