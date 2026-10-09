# The workspace's tab counts (docs/p9/02-support-tickets.md).
#
# Four numbers in one grouped query plus two cheap counts, not six list requests. The scope is the caller's own
# policy scope, so the counts can never describe cases the caller cannot open -- a tab reading "12" over a list
# of 3 would be a disclosure, not a cosmetic bug.
class Support::Tickets::Counts
  def initialize(scope:, user:)
    @scope = scope
    @user = user
  end

  def call
    by_status = @scope.group(:status).count
    {
      all: by_status.values.sum,
      active: by_status.slice(*Support::Ticket::ACTIVE_STATUSES).values.sum,
      mine: @scope.active.where(assignee_id: @user&.id).count,
      unassigned: @scope.active.unassigned.count,
      overdue: @scope.overdue.count,
      resolved: by_status.fetch('resolved', 0),
      closed: by_status.fetch('closed', 0)
    }
  end
end
