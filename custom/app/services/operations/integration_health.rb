# WHAT ONE PARTNER'S INSTALLATION LOOKS LIKE FROM INSIDE LYNOMIA, said to the partner.
#
# THE GAP THIS CLOSES. Store Syria's operators and Lynomia's operators each have a console
# and neither can see the other's. Every incident in the Phase 5 register is of that shape: a
# token rejected unattended, a store dropping out of the counted set, an outbound consent
# decision retired, a campaign blocked for a missing capability. In every one of them the
# facts existed on one side while the person who had to act was on the other.
#
# A PROJECTION, NOT A SECOND HEALTH MODEL. Lynomia already decides what healthy means --
# Operations::Health, Commerce::StoreHealth, Operations::Signal. This selects from those and
# renames nothing, so the two consoles cannot drift into disagreeing about the same store.
#
# WHAT A PARTNER MAY SEE, and why the allow-list is written out rather than implied by
# `as_json`. Operations::AccountSnapshot is the same question asked by a Lynomia operator and
# it carries support cases and operator activity, which are Lynomia's internal business and
# not the partner's. Everything below is an id, a count, an enum, a timestamp or one of
# Lynomia's own classified error codes. There is nowhere here to put a credential, a customer,
# a phone number or a provider response body.
#
# CONFINED TO THE CALLING APP, not merely to the account. `partner_consents` and their event
# log are scoped by `platform_app`, so a second integration on the same workspace cannot read
# this one's consent traffic through an endpoint about health.
#
# BOUNDED. A fixed number of queries whatever the account holds: the stores of one account
# with their snapshot preloaded, one grouped count of their open signals, and three aggregates.
# Nothing here calls a provider -- an operator diagnosing an outage must not be made to wait on
# the thing that is down.
class Operations::IntegrationHealth
  # Signals that are about this integration rather than about the workspace at large. A
  # partner is shown what it can act on; an email channel's authentication problem is the
  # merchant's business with Lynomia, not Store Syria's.
  SOURCES = %w[commerce_store campaign webhook queue].freeze

  # How many of the open signals are LISTED. The count beside them is the real total: a reader
  # who is shown twenty rows and told there are twenty has been told the wrong thing when there
  # are fifty.
  SIGNAL_LIMIT = 20

  def initialize(account, platform_app)
    @account = account
    @platform_app = platform_app
  end

  def call
    components = store_components + [consent_component]

    {
      account: { id: @account.id, name: @account.name },
      status: Operations::Health.worst(components),
      installations: installations,
      signals: { open: open_signal_count, by_source: signals_by_source, recent: recent_signals },
      consent: consent,
      messaging: messaging,
      generated_at: Time.current.utc.iso8601
    }
  end

  private

  def stores
    @stores ||= @account.commerce_stores.includes(:health).order(:id).to_a
  end

  # One row per connected store: what an administrator decided, what the provider has actually
  # done lately, and how the two compare. `status` is the store's own; `observed` is
  # Commerce::StoreHealth, which exists precisely because `active` says nothing about whether
  # the provider answered this week.
  def installations
    stores.map do |store|
      { id: store.id, external_store_id: store.external_store_id, provider: store.provider,
        name: store.name, status: store.status, health: store_health(store) }
    end
  end

  # Commerce::StoreHealth's own words, not a second vocabulary beside them: `api_state` and
  # `webhook_state` are what Lynomia's console shows for this store, and `health_status` is
  # the four-state reading it maps to -- including the escalation to critical at three
  # consecutive failures, which a reimplementation here would have had to remember.
  def store_health(store)
    health = store.health
    return { api_state: 'unknown', webhook_state: 'unknown', status: Operations::Health::UNKNOWN } if health.nil?

    { api_state: health.api_state, webhook_state: health.webhook_state, status: health.health_status,
      last_success_at: iso(health.last_api_success_at), last_failure_at: iso(health.last_api_failure_at),
      last_webhook_at: iso(health.last_webhook_received_at), consecutive_failures: health.consecutive_failures,
      # Lynomia's own classified code and reason -- never a provider response body.
      last_error_code: health.last_error_code, last_error_reason: health.last_error_reason }
  end

  def store_components
    stores.map do |store|
      Operations::Health::Component.build(key: "store_#{store.id}", status: store_status(store),
                                          reason: store.health&.last_error_reason)
    end
  end

  # A store an administrator or a rejected token has taken out of `active` is critical whatever
  # the provider last said: nothing will be delivered for it until somebody acts.
  def store_status(store)
    return Operations::Health::CRITICAL unless store.active?

    store.health&.health_status || Operations::Health::UNKNOWN
  end

  # THE COUNT IS COUNTED, NOT MEASURED OFF THE LIST.
  #
  # `recent` is capped at SIGNAL_LIMIT because a page does not need thirty rows. `open` is how
  # many there are, and taking it from the capped list made it saturate at 20 while
  # `by_source`, in the same payload, went on summing to the real number -- two figures about
  # one installation disagreeing, in a projection whose whole purpose is that the two consoles
  # read the same facts. Both consoles render `open` as "open issues".
  def open_signal_count
    @open_signal_count ||= open_scope.count
  end

  def open_signals
    @open_signals ||= open_scope.recent_first.limit(SIGNAL_LIMIT).to_a
  end

  def open_scope
    Operations::Signal.open_signals.where(account_id: @account.id, source: SOURCES)
  end

  def signals_by_source
    open_scope.group(:source).count
  end

  # The categorisation an operator acts on: where it came from, what was observed, how bad,
  # and the already-redacted reason. Never the detail blob, which is an internal allow-list
  # whose keys are Lynomia's to change.
  def recent_signals
    open_signals.map do |signal|
      { source: signal.source, signal: signal.signal, severity: signal.severity,
        subject_type: signal.subject_type, subject_id: signal.subject_id, reason: signal.reason,
        first_seen_at: iso(signal.first_seen_at), last_seen_at: iso(signal.last_seen_at),
        occurrences: signal.occurrences }
    end
  end

  # Is the consent feed moving, and in which direction. Counts only -- who consented to what
  # is the merchant's and the shopper's, and a health endpoint is not where it is read.
  def consent
    scope = PartnerConsent.where(account_id: @account.id, platform_app_id: @platform_app.id)
    last_event = PartnerConsentEvent.where(account_id: @account.id, platform_app_id: @platform_app.id)
                                    .order(id: :desc).first

    { decisions_held: scope.count, blocking: scope.blocking.count,
      last_event_at: iso(last_event&.received_at), last_event_outcome: last_event&.outcome }
  end

  def consent_component
    key = 'consent_sync'
    last = PartnerConsentEvent.where(account_id: @account.id, platform_app_id: @platform_app.id).order(id: :desc).first
    return Operations::Health.absent(key, 'no consent event received yet') if last.nil?

    Operations::Health::Component.build(key: key, status: Operations::Health::HEALTHY,
                                        observed_at: last.received_at)
  end

  # Whether this workspace can send at all, and what is currently stopped. A campaign blocked
  # for a missing capability is the single most common thing a merchant reports to the partner
  # rather than to Lynomia, because the partner is who they bought it from.
  def messaging
    campaigns = Campaign.where(account_id: @account.id)

    { campaigns_by_status: campaigns.group(:campaign_status).count,
      blocked: campaigns.where.not(blocked_reason: nil).count,
      whatsapp_inboxes: @account.inboxes.where(channel_type: 'Channel::Whatsapp').count }
  end

  def iso(time) = time&.utc&.iso8601
end
