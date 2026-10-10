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
    accounts = Account.includes(:billing_subscription).order(:id).page(@page).per(@per_page)
    ids = accounts.map(&:id)
    data = aggregate(ids)
    { accounts: accounts, rows: accounts.map { |account| row_for(account, data) } }
  end

  private

  # Eight grouped queries, each restricted to the ids on this page.
  def aggregate(ids)
    {
      signals: Operations::Signal.open_signals.where(account_id: ids).group(:account_id).count,
      critical_signals: Operations::Signal.open_signals.where(account_id: ids, severity: :critical)
                                          .group(:account_id).count,
      # Grouped by channel type as well as account, because whether an account's channels can be called healthy
      # depends on WHICH channels they are: five of the twelve report nothing about their own connection
      # (Channels::Capability), and an account made only of those cannot be green.
      inboxes: Inbox.where(account_id: ids).group(:account_id, :channel_type).count,
      # Distinct inboxes, not signal rows: two problems with one inbox is one broken channel.
      broken_channels: inbox_signal_counts(ids, severity: :critical),
      flagged_channels: inbox_signal_counts(ids),
      active_cases: Support::Ticket.active.where(account_id: ids).group(:account_id).count,
      overdue_cases: Support::Ticket.overdue.where(account_id: ids).group(:account_id).count,
      broken_stores: Commerce::Store.where(account_id: ids, status: [:needs_reauth, :disconnected])
                                    .group(:account_id).count
    }
  end

  # Scoped on `subject_type` rather than on a list of sources, so a channel problem recorded by a writer that
  # does not exist yet is still counted here.
  def inbox_signal_counts(ids, severity: nil)
    scope = Operations::Signal.open_signals.where(account_id: ids, subject_type: 'Inbox')
    scope = scope.where(severity: severity) if severity
    scope.group(:account_id).distinct.count(:subject_id)
  end

  def row_for(account, data)
    components = [
      account_component(account),
      billing_component(account),
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

  # A billing-locked account is the commonest reason a customer says "nothing works", and this page said
  # HEALTHY for one until P11: `account_component` reads `accounts.status`, which a billing lock never touches
  # (docs/p11/07-security-performance.md §2). A warning rather than a critical, for the same reason a
  # suspension is one -- the account is switched off, not broken, and the operator needs to see it to explain
  # why nothing is happening. Read off the association preloaded with the page, so no query per row.
  def billing_component(account)
    return Operations::Health.absent(:billing, 'Billing is not configured') unless Billing::Settings.enforced?

    subscription = account.billing_subscription
    return Operations::Health.absent(:billing, 'No subscription record') if subscription.nil?

    locked = !subscription.accessible?
    build(:billing, locked ? Operations::Health::WARNING : Operations::Health::HEALTHY,
          reason: locked ? "Subscription is #{subscription.status}" : nil,
          detail: { code: subscription.status })
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
  #
  # Before P10 this said HEALTHY the moment an account had one inbox, whatever state that inbox was in -- the
  # broken channel was visible only in the generic `recorded_issues` column. Now the column means what it says.
  # It reads the durable `operations_signals` rows rather than calling Channels::ConnectionState per inbox,
  # because this page renders 25 accounts at once and that would be a Redis read and a channel load per inbox.
  # The cost of that choice, stated rather than hidden: a channel that was already broken before P9 shipped has
  # a Redis latch but no signal row, so it is counted as unreported rather than as broken.
  def channels_component(account, data)
    by_type = channel_types_for(account, data)
    return Operations::Health.absent(:channels, 'No inbox is configured') if by_type.empty?

    broken = data[:broken_channels][account.id].to_i
    flagged = data[:flagged_channels][account.id].to_i
    detail = { size: by_type.values.sum, broken: broken, flagged: flagged }
    channel_status(broken, flagged, by_type, detail)
  end

  def channel_status(broken, flagged, by_type, detail)
    return channels(Operations::Health::CRITICAL, "#{broken} channels cannot connect", detail) if broken.positive?
    return channels(Operations::Health::WARNING, "#{flagged} channels reported a problem", detail) if flagged.positive?

    silent = silent_channel_count(by_type)
    return channels(Operations::Health::HEALTHY, nil, detail) if silent.zero?

    # P9's rule, applied to channels: silence is not green. A channel nothing reports on is `unknown`, and an
    # account holding one cannot be summarised as healthy on the strength of the others.
    Operations::Health::Component.build(
      key: :channels, status: Operations::Health::UNKNOWN, source_class: 'absent',
      reason: "#{silent} channels do not report whether they are connected",
      detail: detail.merge(unreported: silent), observed_at: Time.current
    )
  end

  # A channel with no provider -- a web widget, an API inbox -- is not silent, it has nothing to be silent
  # about. A channel type this installation does not describe counts as silent.
  def silent_channel_count(by_type)
    by_type.sum { |channel_type, count| silent_channel_type?(channel_type) ? count : 0 }
  end

  def silent_channel_type?(channel_type)
    entry = Channels::Capability.for_channel_type(channel_type)
    # A channel type this installation does not describe is silent by definition.
    return true if entry.nil?

    entry.provider_backed? && !entry.health_reported?
  end

  def channel_types_for(account, data)
    data[:inboxes].each_with_object({}) do |((account_id, channel_type), count), types|
      types[channel_type] = count if account_id == account.id
    end
  end

  def channels(status, reason, detail)
    build(:channels, status, reason: reason, detail: detail, source_class: 'recorded')
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
