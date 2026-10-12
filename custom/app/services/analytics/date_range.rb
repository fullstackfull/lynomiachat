# The canonical date range for every Lynomia Analytics query (docs/p8/01-architecture.md).
#
# Database timestamps stay UTC. What this object fixes is the *interpretation*: a calendar day means a day in the
# account's own reporting timezone, so two administrators in different places asking for the same dates get the
# same numbers. That is why the inputs are calendar dates and not instants. An instant-based contract cannot give
# that guarantee, because a browser computing "the last 7 days" from its own clock sends a different instant per
# viewer, and the totals would differ per viewer for the same requested period.
#
# The existing /api/v2 reports keep their own epoch-seconds contract and their viewer-offset bucketing; this does
# not change them. The inconsistency between the two is recorded in docs/p8/01-architecture.md.
class Analytics::DateRange
  # A subset of the reports' SUPPORTED_GROUP_BY (hour, day, week, month, year). Only the three a P8 screen
  # actually asks for are accepted; hour and year are added when a screen needs them, not before.
  SUPPORTED_GROUP_BY = %w[day week month].freeze
  DEFAULT_GROUP_BY = 'day'.freeze
  DATE_FORMAT = '%Y-%m-%d'.freeze

  # A ceiling on buckets rather than on days, because buckets are what costs: they are the rows the group-by
  # returns, the points the chart draws and the width of the response. 366 daily / 104 weekly / 60 monthly all
  # come out around a year to five years of readable chart.
  MAX_BUCKETS = { 'day' => 366, 'week' => 104, 'month' => 60 }.freeze

  # What the repository already does when no timezone is known: TimezoneHelper#timezone_name_from_offset returns
  # 'UTC' for a blank offset (app/helpers/timezone_helper.rb:16), and ReportingEvents::RollupService simply does
  # not write a rollup row for an account without one (app/services/reporting_events/rollup_service.rb:25-27).
  # So UTC is the established fallback and not a new invention.
  FALLBACK_TIMEZONE = 'UTC'.freeze

  attr_reader :zone, :group_by, :since_date, :until_date

  def initialize(account:, since:, until_value:, group_by: nil)
    @account = account
    @zone = resolve_zone
    @group_by = resolve_group_by(group_by)
    @since_date = parse_date(since, :since)
    @until_date = parse_date(until_value, :until)
    validate_order!
    validate_bucket_count!
  end

  # Half-open in UTC: [starts_at, ends_at). `until` is inclusive as a *date* -- asking for 1 to 7 October includes
  # the whole of the 7th -- which is expressed as an exclusive instant at the start of the 8th. Half-open is what
  # keeps adjacent ranges from double counting a row on the boundary or dropping one between them.
  def starts_at
    @starts_at ||= @since_date.in_time_zone(@zone).beginning_of_day.utc
  end

  def ends_at
    @ends_at ||= (@until_date + 1).in_time_zone(@zone).beginning_of_day.utc
  end

  def utc_range
    starts_at...ends_at
  end

  # The dates this range covers, in the account's timezone, so a caller can fill empty buckets without
  # recomputing the zone arithmetic.
  def bucket_starts
    step = { 'day' => 1.day, 'week' => 1.week, 'month' => 1.month }.fetch(@group_by)
    cursor = truncate(@since_date.in_time_zone(@zone))
    last = @until_date.in_time_zone(@zone)
    [].tap do |buckets|
      while cursor <= last
        buckets << cursor
        cursor = truncate(cursor + step)
      end
    end
  end

  def bucket_count
    bucket_starts.length
  end

  def to_meta
    {
      since: @since_date.strftime(DATE_FORMAT),
      until: @until_date.strftime(DATE_FORMAT),
      group_by: @group_by,
      timezone: @zone,
      starts_at: starts_at.iso8601,
      ends_at: ends_at.iso8601,
      boundaries: 'start inclusive, end exclusive'
    }
  end

  private

  def resolve_zone
    configured = @account.reporting_timezone.presence
    return FALLBACK_TIMEZONE if configured.blank?
    # An invalid stored value would otherwise raise deep inside the query. Account validates this on write
    # (app/models/account.rb:217-220), so reaching here means the row predates the validation.
    return FALLBACK_TIMEZONE if ActiveSupport::TimeZone[configured].blank?

    configured
  end

  def resolve_group_by(value)
    return DEFAULT_GROUP_BY if value.blank?

    normalized = value.to_s
    unless SUPPORTED_GROUP_BY.include?(normalized)
      raise CustomExceptions::Analytics::InvalidGroupBy.new(group_by: normalized, allowed: SUPPORTED_GROUP_BY)
    end

    normalized
  end

  def parse_date(value, field)
    raise CustomExceptions::Analytics::MissingDate.new(field: field) if value.blank?

    Date.strptime(value.to_s, DATE_FORMAT)
  rescue ArgumentError, TypeError
    raise CustomExceptions::Analytics::InvalidDate.new(field: field, value: value.to_s, expected_format: 'YYYY-MM-DD')
  end

  def validate_order!
    return if @since_date <= @until_date

    raise CustomExceptions::Analytics::InvertedRange.new(
      since: @since_date.strftime(DATE_FORMAT), until: @until_date.strftime(DATE_FORMAT)
    )
  end

  def validate_bucket_count!
    maximum = MAX_BUCKETS.fetch(@group_by)
    return if bucket_count <= maximum

    raise CustomExceptions::Analytics::RangeTooLarge.new(
      group_by: @group_by, buckets: bucket_count, maximum: maximum
    )
  end

  def truncate(time)
    case @group_by
    when 'day' then time.beginning_of_day
    when 'week' then time.beginning_of_week
    when 'month' then time.beginning_of_month
    end
  end
end
