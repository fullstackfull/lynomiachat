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
  # How many inboxes and stores a single account's page reads. An account with more than this has an
  # operational problem of its own, and the page says so rather than rendering five hundred rows.
  LIST_LIMIT_INBOXES = 50

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

  # The connection state of each inbox, live -- which on ONE account is the right trade and on a list of
  # accounts is not.
  #
  # `Channels::ConnectionState` is the product's own per-inbox answer and its documentation says plainly not to
  # call it per inbox across accounts; Operations::AccountHealth uses the durable signals instead for exactly
  # that reason. Here there is one account, at most LIST_LIMIT_INBOXES inboxes, and the state is read from
  # Redis and the channel's own columns -- no provider request, so a page of a broken account cannot hang on
  # the broken provider. `includes(:channel)` loads the polymorphic channels in one query per type rather than
  # one per inbox.
  #
  # The recorded signals are shown beside the live state, not instead of it: the live reading says what is true
  # now, the signal says what was observed and when, and an operator needs both to tell a blip from a week of
  # failure.
  def channels
    inboxes = @account.inboxes.includes(:channel).order(:id).limit(LIST_LIMIT_INBOXES).to_a
    worst = Operations::Signal.open_signals
                              .where(subject_type: 'Inbox', subject_id: inboxes.map(&:id))
                              .group(:subject_id).maximum(:severity)

    inboxes.map do |inbox|
      {
        id: inbox.id,
        name: inbox.name,
        channel_type: inbox.channel_type,
        # The live component, carrying its own status, reason and -- importantly -- `source_class: 'absent'`
        # for the five channel types this fork reports nothing about. That is the console's standing rule: an
        # inbox that can never report reads `unknown`, never healthy.
        connection: Channels::ConnectionState.new(inbox).call,
        worst_open_signal: worst[inbox.id] && Operations::Signal.severities.key(worst[inbox.id])
      }
    end
  end

  # Each store's status PLUS whether its provider is actually answering. The status alone says what an
  # administrator or a token rejection last decided; Commerce::StoreHealth is the only thing that says whether
  # the provider has answered a request recently (docs/product-refinement/09-commerce-operations.md).
  #
  # `includes(:health)` so this is two queries however many stores the account has.
  def stores
    @account.commerce_stores.includes(:health).order(:id).limit(LIST_LIMIT_INBOXES).map do |store|
      health = store.health
      {
        id: store.id,
        provider: store.provider,
        name: store.name,
        status: store.status,
        # `needs_reauth` is the one an operator can act on by telling the merchant to reconnect.
        needs_reauth: store.needs_reauth?,
        # 'unknown' for a store with no snapshot: nobody has called it since recording began, which is not the
        # same as it being fine.
        api_state: health&.api_state || 'unknown',
        last_api_success_at: health&.last_api_success_at,
        last_error_code: health&.last_error_code,
        last_error_at: health&.last_error_at,
        webhook_state: health&.webhook_state || (Commerce::StoreHealth.webhooks?(store.provider) ? 'none' : 'unsupported'),
        last_webhook_received_at: health&.last_webhook_received_at
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

  # The account's support history, and THE SEAM the Platform Support Desk plugs into.
  #
  # Platform Support is deliberately not implemented here (docs/platform-support/11-approved-decisions.md): that
  # phase is frozen at discovery. What this phase owes it is a place to arrive, and this is it -- the one method
  # that answers "what support history does this account have". A Platform Support ticket count becomes one
  # more key in this hash and one more line in the view's support block; no other file changes, because nothing
  # else in the console asks that question, and the view renders this section from named keys rather than from
  # whatever happens to be in the hash.
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
