# The response shape every Lynomia Analytics endpoint returns (docs/p8/02-analytics.md).
#
# One envelope, four payload primitives, so the frontend learns the contract once instead of per endpoint, and
# so the meta block that says *how* a number was produced travels with the number rather than being implied.
#
# The meta block is the honest part. It names the timezone the buckets were cut in, the exact half-open instants
# the range resolved to, which source answered (raw or rollup) and why, and whether anything was left out. A
# chart that cannot say which timezone it used is a chart nobody can reconcile against another report.
class Analytics::Result
  # A single headline number. `comparison` is the same metric over the preceding period of equal length when a
  # caller asked for it, so "up or down" is answerable without a second request.
  Kpi = Data.define(:key, :value, :unit, :comparison) do
    def as_json(*)
      { key: key.to_s, value: value, unit: unit.to_s, comparison: comparison }.compact
    end
  end

  # Points are emitted for every bucket in the range including the empty ones, so a chart does not have to infer
  # a gap, and so a zero day is visibly zero rather than missing.
  Series = Data.define(:key, :unit, :points) do
    def as_json(*)
      { key: key.to_s, unit: unit.to_s, points: points.map { |point| { bucket: point[:bucket], value: point[:value] } } }
    end
  end

  # A grouping by something other than time: inbox, agent, template, provider.
  Breakdown = Data.define(:key, :dimension, :unit, :rows) do
    def as_json(*)
      {
        key: key.to_s, dimension: dimension.to_s, unit: unit.to_s,
        rows: rows.map { |row| { id: row[:id], label: row[:label], value: row[:value] } }
      }
    end
  end

  attr_reader :warnings

  def initialize(family:, date_range:, filters: nil, source: :raw, source_reason: nil)
    @family = family.to_s
    @date_range = date_range
    @filters = filters
    @source = source
    @source_reason = source_reason
    @kpis = []
    @series = []
    @breakdowns = []
    @warnings = []
  end

  def add_kpi(key, value, unit: :count, comparison: nil)
    @kpis << Kpi.new(key: key, value: value, unit: unit, comparison: comparison)
    self
  end

  def add_series(key, points, unit: :count)
    @series << Series.new(key: key, unit: unit, points: points)
    self
  end

  def add_breakdown(key, dimension, rows, unit: :count)
    @breakdowns << Breakdown.new(key: key, dimension: dimension, unit: unit, rows: rows)
    self
  end

  # A named part of the response could not be produced, but the rest can. The frontend shows what it has and says
  # so. This is for an optional contributor, never for an authorization or a primary-query failure: those raise.
  def degrade(scope, reason)
    @warnings << { scope: scope.to_s, reason: reason.to_s }
    self
  end

  # True when nothing was found but everything worked -- the difference between "no data" and "something broke",
  # which the two states must not be allowed to blur into each other.
  def empty?
    @warnings.empty? && blank_kpis? && blank_series? && blank_breakdowns?
  end

  def partial?
    @warnings.any?
  end

  def as_json(*)
    {
      meta: meta,
      kpis: @kpis.map(&:as_json),
      series: @series.map(&:as_json),
      breakdowns: @breakdowns.map(&:as_json)
    }
  end

  private

  def blank_kpis?
    @kpis.all? { |kpi| kpi.value.to_f.zero? }
  end

  def blank_series?
    @series.all? { |series| series.points.all? { |point| point[:value].to_f.zero? } }
  end

  def blank_breakdowns?
    @breakdowns.all? { |breakdown| breakdown.rows.empty? }
  end

  def meta
    {
      family: @family,
      empty: empty?,
      partial: partial?,
      source: @source.to_s,
      source_reason: @source_reason&.to_s,
      filters: @filters&.to_meta || {},
      warnings: @warnings
    }.compact.merge(@date_range.to_meta)
  end
end
