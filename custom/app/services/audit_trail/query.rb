# One page of one account's audit trail (docs/p-final/clean-room/specs/A-audit-trail-read.md §2, §4).
#
# The account comes from the authenticated session and is the first thing applied, so no combination of filter,
# sort or page can reach another account's entries. The capability is checked here rather than in the controller
# because an account without the audit capability must get an empty page and a 200, not a refusal: the page then
# renders its own empty state instead of an error.
#
# `includes(:auditable)` is what keeps the query count flat. It costs one extra query per auditable TYPE on the
# page, which is bounded by the vocabulary rather than by the page size, and it is needed because a membership
# entry's label depends on whether the actor edited themselves -- which the browser decides from the auditable's
# own user id (app/javascript/dashboard/helper/auditlogHelper.js:218).
class AuditTrail::Query
  CAPABILITY = 'audit_logs'.freeze

  def initialize(account:, params: {})
    @account = account
    @filters = AuditTrail::Filters.new(params)
  end

  attr_reader :filters

  def entries
    @entries ||= scope.page(@filters.page).per(@filters.per_page)
  end

  def total_entries
    entries.total_count
  end

  def current_page
    entries.current_page
  end

  def per_page
    @filters.per_page
  end

  private

  def scope
    return Custom::AuditLog.none unless @account.feature_enabled?(CAPABILITY)

    filtered(Custom::AuditLog.for_account(@account)).includes(:auditable)
  end

  def filtered(scope)
    scope = scope.of_type(@filters.types) if @filters.types
    scope = scope.by_actor(@filters.actor_id) if @filters.actor_id
    scope = scope.occurred_between(@filters.window.first, @filters.window.last) if @filters.window
    @filters.sort == 'asc' ? scope.oldest_first : scope.newest_first
  end
end
