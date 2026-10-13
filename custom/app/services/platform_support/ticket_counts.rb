# The three numbers the tenant list's header shows
# (docs/platform-support/12-refresh-against-product-refinement.md §2 `meta.counts`).
#
# Two queries, not three list requests: one grouped count covers both status groups, and `unread` is a
# predicate over two columns rather than a stored flag, so it needs no notification row to be true.
#
# The scope is the CALLER'S OWN policy scope, so these counts can never describe tickets the caller cannot
# open. A header reading "12" over a list of 3 would be a disclosure, not a cosmetic bug.
class PlatformSupport::TicketCounts
  def initialize(scope:)
    @scope = scope
  end

  def call
    by_status = @scope.group(:status).count
    {
      open: by_status.slice(*PlatformSupport::Ticket::OPEN_STATUSES).values.sum,
      closed: by_status.slice(*PlatformSupport::Ticket::CLOSED_STATUSES).values.sum,
      unread: @scope.unread.count
    }
  end
end
