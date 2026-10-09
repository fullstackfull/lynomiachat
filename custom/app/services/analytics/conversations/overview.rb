# Assembles the Lynomia Analytics overview response (docs/p8/02a-overview-conversation-analytics.md).
#
# One request answers the operational questions an overview screen exists for -- how much work arrived, how much
# was closed, how much is still open, how fast we respond, and where the volume sits -- rather than making the
# frontend stitch eight endpoints together.
class Analytics::Conversations::Overview
  BREAKDOWN_DIMENSIONS = %i[inbox channel team agent].freeze
  DEFAULT_BREAKDOWN = :inbox
  SERIES_METRICS = %i[conversations_created conversations_resolved inbound_messages outbound_messages].freeze
  DURATION_METRICS = %i[avg_first_response_time avg_resolution_time].freeze

  def initialize(account:, date_range:, filters:, breakdown_by: nil)
    @account = account
    @date_range = date_range
    @filters = filters
    @breakdown_by = resolve_breakdown(breakdown_by)
    @metrics = Analytics::Conversations::Metrics.new(account: account, date_range: date_range, filters: filters)
  end

  def call
    result = Analytics::Result.new(
      family: :conversations, date_range: @date_range, filters: @filters,
      source: rollup_decision.source, source_reason: rollup_decision.reason
    )

    add_kpis(result)
    SERIES_METRICS.each { |metric| result.add_series(metric, @metrics.series(metric)) }
    result.add_breakdown(:"by_#{@breakdown_by}", @breakdown_by, @metrics.breakdown(@breakdown_by))
    result
  end

  private

  def add_kpis(result)
    Analytics::Conversations::Metrics::EVENT_METRICS.each do |metric|
      unit = DURATION_METRICS.include?(metric) ? :seconds : :count
      result.add_kpi(metric, @metrics.public_send(metric), unit: unit, kind: :event)
    end
    Analytics::Conversations::Metrics::CURRENT_STATE_METRICS.each do |metric|
      result.add_kpi(metric, @metrics.public_send(metric), kind: :current_state)
    end
  end

  # The overview reads raw throughout. It is reported rather than assumed: the decision object names which source
  # answered and why, so `source_reason` tells an operator whether the rollup was skipped because the feature is
  # off, because no timezone is set, or because its coverage did not agree with the raw events.
  #
  # Rollups are not consulted per metric here because this screen mixes metrics that have no rollup counterpart
  # (message counts, reopens, backlog) with ones that do, and splitting the sources within one response is
  # exactly what Analytics::RollupCoverage exists to prevent.
  def rollup_decision
    @rollup_decision ||= Analytics::RollupCoverage.new(
      account: @account, date_range: @date_range, family: :conversations,
      metric: :resolutions_count, dimension_type: 'account'
    ).decide
  end

  def resolve_breakdown(value)
    return DEFAULT_BREAKDOWN if value.blank?

    normalized = value.to_s.to_sym
    return normalized if BREAKDOWN_DIMENSIONS.include?(normalized)

    raise CustomExceptions::Analytics::UnsupportedBreakdown.new(
      breakdown: value.to_s, allowed: BREAKDOWN_DIMENSIONS.map(&:to_s)
    )
  end
end
