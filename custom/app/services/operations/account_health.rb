# One page of accounts, each with its component statuses (docs/p9/04-operations-center.md §account health).
#
# COMPONENT STATUSES, NEVER A SCORE. There is no "87% healthy": a score is a number nobody can act on, and
# averaging an unknown into it would turn missing information into a reassuring digit. Each component stands or
# falls on its own, and the row's badge is the worst of them.
#
# NO N+1, BY CONSTRUCTION. The existing Super Admin accounts index pays two uncached COUNT queries per row
# through CountField (app/fields/count_field.rb:3-7) -- 40 queries for a page of 20. This takes one page of
# accounts and then one GROUPED query per component restricted to that page's ids, so the query count is fixed
# whatever the page size.
class Operations::AccountHealth
  PER_PAGE = 25

  def initialize(page: nil, per_page: PER_PAGE)
    @page = page
    @per_page = per_page.to_i.clamp(1, 100)
  end

  def call
    accounts = Account.order(:id).page(@page).per(@per_page)
    ids = accounts.map(&:id)
    data = aggregate(ids)
    { accounts: accounts, rows: accounts.map { |account| row_for(account, data) } }
  end

  private

  # Six grouped queries, each restricted to the ids on this page.
  def aggregate(ids)
    {
      signals: Operations::Signal.open_signals.where(account_id: ids).group(:account_id).count,
      critical_signals: Operations::Signal.open_signals.where(account_id: ids, severity: :critical)
                                          .group(:account_id).count,
      inboxes: Inbox.where(account_id: ids).group(:account_id).count,
      active_cases: Support::Ticket.active.where(account_id: ids).group(:account_id).count,
      overdue_cases: Support::Ticket.overdue.where(account_id: ids).group(:account_id).count,
      broken_stores: Commerce::Store.where(account_id: ids, status: [:needs_reauth, :disconnected])
                                    .group(:account_id).count
    }
  end

  def row_for(account, data)
    components = [
      account_component(account),
      signals_component(account, data),
      channels_component(account, data),
      commerce_component(account, data),
      cases_component(account, data)
    ]
    { account: account, components: components, status: Operations::Health.worst(components) }
  end

  # A suspended account is not broken, it is switched off, so it is a warning and not a critical: an operator
  # needs to see it to explain why nothing is happening, not to fix it.
  def account_component(account)
    suspended = account.status.to_s != 'active'
    build(:account_status, suspended ? Operations::Health::WARNING : Operations::Health::HEALTHY,
          reason: suspended ? "Account is #{account.status}" : nil, detail: { code: account.status.to_s })
  end

  def signals_component(account, data)
    open_count = data[:signals][account.id].to_i
    critical = data[:critical_signals][account.id].to_i
    status = signals_status(critical, open_count)
    build(:recorded_issues, status, source_class: 'recorded',
                                    reason: open_count.zero? ? nil : "#{open_count} open operational issues",
                                    detail: { size: open_count, critical: critical })
  end

  def signals_status(critical, open_count)
    return Operations::Health::CRITICAL if critical.positive?
    return Operations::Health::WARNING if open_count.positive?

    Operations::Health::HEALTHY
  end

  # An account with no inbox cannot receive anything. That is almost always a half-finished setup rather than a
  # fault, so it is `unknown` with the reason rather than a failure badge.
  def channels_component(account, data)
    count = data[:inboxes][account.id].to_i
    return Operations::Health.absent(:channels, 'No inbox is configured') if count.zero?

    build(:channels, Operations::Health::HEALTHY, detail: { size: count })
  end

  def commerce_component(account, data)
    broken = data[:broken_stores][account.id].to_i
    return Operations::Health.absent(:commerce, 'No commerce store is connected') unless account.feature_enabled?('lynomia_commerce')

    build(:commerce, broken.zero? ? Operations::Health::HEALTHY : Operations::Health::CRITICAL,
          reason: broken.zero? ? nil : "#{broken} stores need to be reconnected", detail: { size: broken })
  end

  # Support cases are a reading of the account's own workload, not of our infrastructure, so an overdue case is
  # a warning for the operator to raise with the customer rather than something we broke.
  def cases_component(account, data)
    return Operations::Health.absent(:support_cases, 'Support cases are not enabled') unless
      account.feature_enabled?('lynomia_support_tickets')

    active = data[:active_cases][account.id].to_i
    overdue = data[:overdue_cases][account.id].to_i
    build(:support_cases, overdue.zero? ? Operations::Health::HEALTHY : Operations::Health::WARNING,
          reason: overdue.zero? ? nil : "#{overdue} cases are past their resolution target",
          detail: { size: active, overdue: overdue })
  end

  def build(key, status, reason: nil, detail: {}, source_class: 'computed')
    Operations::Health::Component.build(key: key, status: status, reason: reason, detail: detail,
                                        source_class: source_class, observed_at: Time.current)
  end
end
