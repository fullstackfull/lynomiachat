# Decides whether reporting_events_rollups may answer a request, or whether it has to be raw events
# (docs/p8/01-architecture.md).
#
# Raw is the source of truth. The rollup is an optimisation and never the only place an answer comes from.
#
# The decision is **all or nothing for the whole requested range**. Serving part of a range from rollups and the
# rest from raw is the one thing this must not do: the rollup upsert is additive
# (app/services/reporting_events/rollup_service.rb:73-79, `count = count + EXCLUDED.count`), so a day that was
# rolled up twice reads high, and a day before the rollup began reads zero. Mixing the two sources would publish
# a number that is part double-counted and part missing, with nothing in the response to say so. Choosing one
# source for the entire range means a wrong rollup shows up as a refused rollup, not as a wrong total.
#
# Four conditions, all required:
#   1. the account has the report_rollup read feature enabled -- it is `enabled: false` in config/features.yml
#      and a migration disabled it for every existing account, so this is off unless an operator turned it on;
#   2. the account has a valid reporting_timezone -- without it RollupService writes nothing at all, so there is
#      no rollup to read;
#   3. a rollup dimension exists for what was asked -- the writer only populates account, agent and inbox;
#   4. every bucket in the range is present in the rollup, and the rollup's own daily totals agree with the raw
#      events for the same days.
#
# Condition 4 is the expensive one, so it is only reached when 1 to 3 pass, which on a default installation is
# never. The cost of the check is bounded by the range, which Analytics::DateRange has already capped.
class Analytics::RollupCoverage
  Decision = Data.define(:source, :reason) do
    def rollup?
      source == :rollup
    end
  end

  ROLLUP_DIMENSIONS = %w[account agent inbox].freeze

  def initialize(account:, date_range:, family:, metric:, dimension_type: 'account')
    @account = account
    @date_range = date_range
    @family = family
    @metric = metric
    @dimension_type = dimension_type.to_s
  end

  def decide
    return raw_decision(:feature_disabled) unless @account.feature_enabled?(:report_rollup)
    return raw_decision(:no_account_reporting_timezone) if @account.reporting_timezone.blank?
    return raw_decision(:no_rollup_dimension) unless ROLLUP_DIMENSIONS.include?(@dimension_type)
    return raw_decision(:no_rollup_metric) unless Analytics::MetricFamily.rollup_candidate?(@family, @metric)
    return raw_decision(:incomplete_coverage) unless fully_covered?

    Decision.new(source: :rollup, reason: :coverage_verified)
  end

  private

  # Named raw_decision and not raw: `raw` is a Rails view helper, so a private method of that name makes
  # Rails/OutputSafety fire on every call site.
  def raw_decision(reason)
    Decision.new(source: :raw, reason: reason)
  end

  # The rollup is bucketed by the account's reporting timezone (rollup_service.rb:29-31), which is the same
  # timezone Analytics::DateRange uses, so the two agree on what a day is and the comparison is meaningful.
  #
  # Agreement is checked over the UNION of the days either side reports, not just the days the raw side has.
  # Iterating the raw side alone would declare coverage whenever raw is empty -- `{}.all?` is true -- so an
  # account with no events and a stale rollup row would read the rollup and report activity that never happened.
  def fully_covered?
    rollup = rollup_daily_counts
    raw = raw_daily_counts
    return false if rollup.empty? && raw.empty?

    (rollup.keys | raw.keys).all? { |day| rollup[day].to_i == raw[day].to_i }
  end

  def rollup_daily_counts
    spec = ReportingEvents::MetricRegistry::REPORT_METRICS.fetch(@metric.to_sym, {})
    rollup_metric = spec[:rollup_metric]
    return {} if rollup_metric.blank?

    ReportingEventsRollup
      .where(account_id: @account.id, dimension_type: @dimension_type,
             metric: rollup_metric, date: @date_range.since_date..@date_range.until_date)
      .group(:date).sum(:count)
  end

  def raw_daily_counts
    spec = ReportingEvents::MetricRegistry::REPORT_METRICS.fetch(@metric.to_sym, {})
    event_name = spec[:raw_event_name]
    return {} if event_name.blank?

    ReportingEvent
      .where(account_id: @account.id, name: event_name.to_s, created_at: @date_range.utc_range)
      .group(Arel.sql("(created_at AT TIME ZONE 'UTC' AT TIME ZONE #{ReportingEvent.connection.quote(@date_range.zone)})::date"))
      .count
  end
end
