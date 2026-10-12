# Every connected store, and whether it is actually working (docs/product-refinement/09-commerce-operations.md).
#
# WHAT THIS ANSWERS THAT NOTHING ELSE DID. `commerce_stores.status` says what an administrator or a rejected
# token last decided. It does not say whether the provider has answered a request this week, so a store quietly
# failing since Tuesday and a store syncing every minute both read `active`. This pairs the status with
# Commerce::StoreHealth -- the operational snapshot the provider path writes -- and with the store's open
# incidents, so an operator can tell those two apart.
#
# NOTHING HERE CALLS A PROVIDER. Every value is one the product already stored. An operator diagnosing an
# outage must not be made to wait on the thing that is down, and a page that probed each store would take as
# long as the slowest broken store's timeout.
#
# BOUNDED. One aggregate for the summary, one page of stores with their account and snapshot preloaded, and one
# grouped query for their open incidents. Five queries whether the installation has three stores or three
# thousand.
class Operations::CommerceOperations
  PER_PAGE = 50

  # The views an operator actually works from. `needs_action` is the default because it is the question being
  # asked: which stores does somebody have to do something about.
  VIEWS = {
    'needs_action' => 'Needs action',
    'failing' => 'Provider failing',
    'unobserved' => 'No signal yet',
    'all' => 'All stores'
  }.freeze
  DEFAULT_VIEW = 'needs_action'.freeze

  def initialize(params: {})
    @params = params || {}
  end

  def view = VIEWS.key?(@params[:view].to_s) ? @params[:view].to_s : DEFAULT_VIEW

  def call
    { view: view, views: VIEWS, summary: summary, rows: rows, generated_at: Time.current }
  end

  # Five counts in ONE statement, so the tab labels cannot disagree with the list under them -- the same shape
  # Operations::AttentionQueue#counts uses, for the same reason.
  #
  # `unobserved` is the honest one: a store with no snapshot, or a snapshot that has never seen either an answer
  # or a failure, is UNKNOWN. It is not healthy and it is not broken, and this console never rounds the
  # difference away.
  def summary
    @summary ||= ActiveRecord::Base.connection.select_one(
      ActiveRecord::Base.sanitize_sql_array(
        ["SELECT COUNT(*) AS stores,
                 COUNT(*) FILTER (WHERE s.status = :needs_reauth) AS needs_reauth,
                 COUNT(*) FILTER (WHERE s.status = :disabled) AS disabled,
                 COUNT(*) FILTER (WHERE h.consecutive_failures > 0) AS failing,
                 COUNT(*) FILTER (WHERE h.id IS NULL
                                    OR (h.last_api_success_at IS NULL AND h.last_api_failure_at IS NULL)) AS unobserved,
                 COUNT(*) FILTER (WHERE h.consecutive_failures = 0 AND h.last_api_success_at < :cutoff) AS stale
          FROM commerce_stores s
          LEFT JOIN commerce_store_health h ON h.commerce_store_id = s.id
          WHERE s.status <> :disconnected",
         { needs_reauth: Commerce::Store.statuses[:needs_reauth], disabled: Commerce::Store.statuses[:disabled],
           disconnected: Commerce::Store.statuses[:disconnected],
           cutoff: Time.current - Commerce::StoreHealth::STALE_AFTER }]
      )
    ).symbolize_keys
  end

  private

  def rows
    stores = scope.includes(:account, :health).order(:account_id, :id).page(@params[:page]).per(PER_PAGE)
    worst = worst_open_signal(stores.map(&:id))
    { page: stores, entries: stores.map { |store| row(store, worst[store.id]) } }
  end

  def row(store, open_signal)
    health = store.health
    {
      store: store,
      account: store.account,
      # `unknown` rather than a blank: a store with no snapshot row has not been observed, and saying so is the
      # point of the column.
      api_state: health&.api_state || 'unknown',
      status: health&.health_status || Operations::Health::UNKNOWN,
      webhook_state: webhook_state(store, health),
      health: health,
      # The last time the whole connection was verified end to end, which the connection lifecycle already
      # records (Commerce::StoreConnection writes it on every connect, rotate and enable). Read from where it
      # already lives rather than copied into a new column.
      verified_at: parse_time(store.metadata['verified_at']),
      open_signal: open_signal
    }
  end

  # A store with no snapshot still has an honest webhook answer: whether its provider has webhooks at all.
  def webhook_state(store, health)
    return health.webhook_state if health

    Commerce::StoreHealth.webhooks?(store.provider) ? 'none' : 'unsupported'
  end

  def scope
    connected = Commerce::Store.connected
    case view
    when 'failing' then connected.joins(:health).where(commerce_store_health: { consecutive_failures: 1.. })
    when 'unobserved' then unobserved(connected)
    when 'all' then connected
    else needs_action(connected)
    end
  end

  # A store with no snapshot at all, and one whose snapshot has never seen either an answer or a failure. Both
  # are the same fact -- nobody has called this store since recording began -- and both must read as one view.
  def unobserved(connected)
    never = Commerce::StoreHealth.where(last_api_success_at: nil, last_api_failure_at: nil).select(:commerce_store_id)
    connected.where.missing(:health).or(connected.where(id: never))
  end

  # What a human has to do something about: an authorization that is gone, or a provider that is refusing. A
  # store nobody has called yet is NOT here -- it is a gap in our knowledge, not a job, and putting it in this
  # list is how an operator learns to ignore the list.
  def needs_action(connected)
    connected.where(status: :needs_reauth)
             .or(connected.where(id: Commerce::StoreHealth.where(consecutive_failures: 1..).select(:commerce_store_id)))
  end

  # One grouped query for the whole page rather than a lookup per row.
  def worst_open_signal(store_ids)
    return {} if store_ids.empty?

    Operations::Signal.open_signals
                      .where(subject_type: 'Commerce::Store', subject_id: store_ids)
                      .group(:subject_id)
                      .maximum(:severity)
                      .transform_values { |severity| Operations::Signal.severities.key(severity) }
  end

  def parse_time(value)
    value.present? ? Time.zone.parse(value.to_s) : nil
  rescue ArgumentError
    nil
  end
end
