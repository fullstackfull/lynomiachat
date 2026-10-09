# Assembles the WhatsApp delivery response (docs/p8/02b-whatsapp-campaign-analytics.md).
class Analytics::Whatsapp::Overview
  BREAKDOWN_DIMENSIONS = %i[template inbox failure].freeze
  DEFAULT_BREAKDOWN = :template
  SERIES_METRICS = %i[messages_sent delivered failed].freeze
  RATE_METRICS = Analytics::Whatsapp::Metrics::RATE_METRICS

  def initialize(account:, date_range:, filters:, breakdown_by: nil)
    @account = account
    @date_range = date_range
    @filters = filters
    @breakdown_by = Analytics::Breakdown.resolve(breakdown_by, BREAKDOWN_DIMENSIONS, DEFAULT_BREAKDOWN)
    @metrics = Analytics::Whatsapp::Metrics.new(account: account, date_range: date_range, filters: filters)
  end

  def call
    # Raw only: ReportingEvents::RollupService writes no WhatsApp delivery dimension, so there is nothing to
    # read even when rollups are otherwise healthy.
    result = Analytics::Result.new(family: :whatsapp, date_range: @date_range, filters: @filters,
                                   source: :raw, source_reason: :no_rollup_metric)

    Analytics::Whatsapp::Metrics::COUNT_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric)) }
    RATE_METRICS.each { |metric| result.add_kpi(metric, @metrics.public_send(metric), unit: :percent) }
    result.add_kpi(:coexistence_echoes, @metrics.coexistence_echoes)

    SERIES_METRICS.each { |metric| result.add_series(metric, @metrics.series(metric)) }
    result.add_breakdown(:"by_#{@breakdown_by}", @breakdown_by, @metrics.breakdown(@breakdown_by))
    result
  end
end
