# Everything an operator needs to understand ONE affected account, in one place
# (docs/product-refinement/07-operations-control-center-v2.md §5).
#
# WHY IT IS A SEPARATE SERVICE FROM Operations::AccountHealth
#
# `AccountHealth` is page-shaped: it answers "which of these 25 accounts is in trouble" and its whole design is
# about not paying per row. This answers "what is going on with THIS account", which is a different question
# with a different budget. One account can afford the reads a list cannot, and pretending otherwise is how a
# detail page ends up as thin as the list it was opened from.
#
# The product decision behind it: an operator must be able to understand an affected account without hunting
# through many disconnected pages. So this gathers identity, commercial state, usage against the plan's own
# limits, channels, commerce stores, open issues, support cases and recent operator activity -- and links out
# to the page that owns each one rather than reimplementing it.
#
# STILL BOUNDED. A fixed number of queries regardless of how much the account has: every collection is either
# a grouped count or a `limit`ed read. Nothing here calls a provider -- no live Meta or Shopify request while a
# page renders, because an operator diagnosing an outage must not be made to wait on the thing that is down.
# The channel and store states shown are the ones the product already stored.
#
# NO SECRETS. Every value is an id, a count, an enum or a name. The services it reads do not expose credentials
# and nothing here reaches for `provider_config` or `credentials`.
class Operations::AccountSnapshot
  RECENT_LIMIT = 10

  def initialize(account)
    @account = account
  end

  def call
    {
      account: identity,
      commercial: commercial,
      usage: usage,
      channels: channels,
      stores: stores,
      signals: signals,
      support: support,
      recent_operator_activity: recent_operator_activity,
      generated_at: Time.current
    }
  end

  private

  def identity
    {
      id: @account.id,
      name: @account.name,
      status: @account.status,
      # The category of a suspension, which is NOT a column: it lives in
      # accounts.internal_attributes['suspensions'] as an append-only history (Account#suspension_history).
      # An operator looking at a suspended account needs to know WHY, and "spam" and "non_payment" are two
      # very different conversations.
      suspension: @account.suspension_history.last&.slice('category', 'reason', 'suspended_at'),
      locale: @account.locale,
      created_at: @account.created_at,
      agents: @account.account_users.count
    }
  end

  def commercial
    subscription = @account.billing_subscription
    return { subscription: nil, plan: nil, accessible: nil } if subscription.nil?

    {
      subscription: { status: subscription.status, source: subscription.source },
      plan: subscription.plan&.slice(:id, :name),
      # The one judgement that decides whether the product works for them at all.
      accessible: subscription.accessible?,
      overrides: Billing::Entitlements.overrides(@account).map { |o| o.slice(:kind, :name) }
    }
  end

  # Usage against the plan's OWN limits, which is the only form of this number that means anything: "3 inboxes"
  # is not a problem or a non-problem until you know the plan allows 2.
  #
  # `nil` limit means unlimited, and is rendered as such rather than as a blank or a zero.
  def usage
    BillingPlan::LIMIT_KEYS.index_with do |resource|
      {
        used: Billing::ResourceLimit.current_count(@account, resource),
        limit: Billing::Entitlements.limit(@account, resource)
      }
    end
  end

  # One grouped query for the channel problems, then the inboxes themselves. The per-inbox state is the one the
  # product already recorded -- an open signal against that inbox -- not a live provider call.
  def channels
    inboxes = @account.inboxes.order(:id).limit(50).to_a
    worst = Operations::Signal.open_signals
                              .where(subject_type: 'Inbox', subject_id: inboxes.map(&:id))
                              .group(:subject_id).maximum(:severity)

    inboxes.map do |inbox|
      capability = Channels::Capability.for_inbox(inbox)
      {
        id: inbox.id,
        name: inbox.name,
        channel_type: inbox.channel_type,
        # Whether this channel reports on its own health AT ALL. `Channels::Capability::Entry#health_reported?`
        # is false for the channels with no health source, and an inbox that can never report is `unknown`
        # rather than healthy -- the console's standing rule, and the reason this is shown per inbox rather
        # than rolled into one badge. `nil` for a channel type the capability table does not know.
        health_reported: capability&.health_reported?,
        worst_open_signal: worst[inbox.id] && Operations::Signal.severities.key(worst[inbox.id])
      }
    end
  end

  def stores
    @account.commerce_stores.order(:id).limit(50).map do |store|
      {
        id: store.id,
        provider: store.provider,
        name: store.name,
        status: store.status,
        # `needs_reauth` is the one an operator can act on by telling the merchant to reconnect.
        needs_reauth: store.needs_reauth?
      }
    end
  end

  def signals
    open = Operations::Signal.open_signals.for_account(@account.id)
    {
      open: open.count,
      by_severity: open.group(:severity).count,
      needing_action: open.attention_queue.count,
      recent: open.recent_first.limit(RECENT_LIMIT).to_a
    }
  end

  def support
    cases = Support::Ticket.where(account_id: @account.id)
    { active: cases.active.count, overdue: cases.overdue.count }
  end

  # What Lynomia's own operators have recently done about this account, read from the incident timeline rather
  # than from the audit log. The audit log answers "who changed product data" and is the record of record; this
  # is the operational story, and it is what an operator picking up somebody else's incident wants.
  def recent_operator_activity
    Operations::SignalEvent.by_operator
                           .joins('INNER JOIN operations_signals ON operations_signals.id = operations_signal_events.operations_signal_id')
                           .where(operations_signals: { account_id: @account.id })
                           .order(created_at: :desc)
                           .limit(RECENT_LIMIT)
                           .to_a
  end
end
