# The audit trail's filter surface, parsed from a request and nothing else
# (docs/p-final/clean-room/specs/A-audit-trail-read.md §2).
#
# Every value here comes from a query string, so every value is parsed leniently: an administrator who lands on
# the page with a stale or hand-edited URL gets a page, not a 500 (specification §2: "Unparseable or
# out-of-range values must not raise"). A value that cannot be understood is simply not applied -- that is the
# documented behaviour, and it keeps this off the exception tracker.
#
# `to_s` before `to_i` for the same reason, and it is load-bearing: a query string can carry any shape, and
# `?page[]=2` arrives as an array, on which `to_i` is not defined.
#
# Two spellings of the type filter are accepted because the shipped page sends `types[]`
# (app/javascript/dashboard/helper/auditlogHelper.js:276 builds `filters.types = [query.type]`) while the
# specification names `type`. Both mean the same thing and neither is going to be changed on the other's account.
class AuditTrail::Filters
  PER_PAGE = 25
  SORT_DIRECTIONS = %w[asc desc].freeze
  DEFAULT_SORT = 'desc'.freeze

  # Nothing is restricted when the client asks for everything. The page's own "all" option sends no parameter at
  # all, but the sentinel is part of the documented surface.
  NO_RESTRICTION = ['all', ''].freeze

  def initialize(params)
    @params = params
  end

  def page
    [@params[:page].to_s.to_i, 1].max
  end

  def per_page
    PER_PAGE
  end

  def sort
    SORT_DIRECTIONS.include?(@params[:sort].to_s) ? @params[:sort].to_s : DEFAULT_SORT
  end

  def types
    values = Array(@params[:types]) + [@params[:type]]
    restricted = values.filter_map { |value| value.to_s.strip.presence }
                       .reject { |value| NO_RESTRICTION.include?(value.downcase) }
    restricted.presence
  end

  def actor_id
    id = @params[:user_id].to_s.to_i
    id.positive? ? id : nil
  end

  # The settings page's search box. It sends `q`
  # (app/javascript/dashboard/routes/dashboard/settings/auditlogs/Index.vue:118-125 through
  # helper/auditlogHelper.js:275), and the page counts it among its active filters, so a value that reached
  # nothing would present an unfiltered trail as a filtered one.
  def actor_name
    @params[:q].to_s.strip.presence
  end

  # Both bounds or neither: a window with one end is a filter the page has no way to express and whose meaning
  # would have to be invented here.
  def window
    from = unix_time(@params[:since])
    to = unix_time(@params[:until])
    return nil if from.nil? || to.nil? || from > to

    from..to
  end

  private

  # The end of 9999, which is past any date this trail can hold and still inside what a PostgreSQL `timestamp`
  # accepts. `Time.zone.at` happily answers year 31690708 for 10**15, so without an upper bound the value
  # becomes a real Time, reaches the database as a literal it rejects, and the request 500s -- which is the one
  # thing the specification says a bad parameter must not do.
  LAST_REPRESENTABLE_SECOND = 253_402_300_799

  # `to_i` would turn "yesterday" into 1970 and silently return an empty page for a window nobody asked for, so
  # the value has to be numeric before it is believed.
  def unix_time(value)
    seconds = Integer(value.to_s, exception: false)
    return nil if seconds.nil? || seconds.negative? || seconds > LAST_REPRESENTABLE_SECOND

    Time.zone.at(seconds)
  end
end
