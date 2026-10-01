# Order actions from a conversation's Commerce section (docs/commerce/28-commerce-actions-architecture.md).
#
#   availability  reads the order from the store now and says, per action, whether this agent can perform it, and why not
#   request       validates and records one action (Commerce::ActionRun, idempotent by its key) and queues it; the store
#                 is written only by Commerce::ActionExecutor, after it has read the order again
#
# An action is possible only when everything agrees, checked in this order:
#   1. the provider implements actions, and this one (else 'unsupported')
#   2. the installation's switches (Commerce::Switches)
#   3. the store's opt-in: an administrator turned order actions on in Settings → Commerce
#   4. the store's credentials can write (a WooCommerce Read/Write key, Shopify's write_orders scope)
#   5. the agent's permission (Commerce::ActionPolicy)
#   6. no earlier action on the order is still unresolved
#   7. the order's state in the store now (the provider's capability)
# The order must be one of the conversation's linked customer's orders in that store: any other order id is not found.
class Commerce::OrderActions
  OWNERSHIP_WINDOW = 25
  ORDER_ID = /\A\d{1,20}\z/
  VERSION = /\A\h{16,64}\z/
  AMOUNT = /\A\d{1,12}(\.\d{1,4})?\z/
  CURRENCY = /\A[A-Z]{3}\z/
  TARGET_STATUSES = %w[processing on_hold completed shipped delivered].freeze
  REFUND_REASONS = %w[customer_request duplicate damaged not_received other].freeze
  CANCEL_REASONS = %w[customer_request inventory fraud payment_declined other].freeze
  RATE_LIMITS = { user: [10, 1.minute], store: [30, 1.minute], order: [5, 10.minutes] }.freeze
  STORE_ERRORS = {
    'unsupported' => 'ACTION_UNAVAILABLE', 'actions_disabled' => 'ACTIONS_DISABLED', 'provider_actions_disabled' => 'ACTIONS_DISABLED',
    'store_actions_off' => 'ACTIONS_DISABLED', 'read_only_key' => 'WRITE_ACCESS_DENIED', 'missing_scope' => 'WRITE_ACCESS_DENIED',
    'write_access_unverified' => 'WRITE_ACCESS_DENIED'
  }.freeze

  # For Settings → Commerce: 'available' when the store's actions could work once its administrator opts in (or has), else
  # why not (unsupported, actions_disabled, provider_actions_disabled, read_only_key, missing_scope, write_access_unverified).
  def self.store_status(store)
    new(store: store, contact_id: nil, user: nil, account_user: nil).store_blocker(opt_in: false) || 'available'
  end

  # Whether the store's actions menu is offered to this user at all (stores list, Customer 360).
  def self.offered?(store, user)
    account_user = store.account.account_users.find_by(user_id: user.id)
    account_user.present? && new(store: store, contact_id: nil, user: user, account_user: account_user).offered?
  end

  def initialize(store:, contact_id:, user:, account_user:, conversation_id: nil)
    @store = store
    @contact_id = contact_id
    @conversation_id = conversation_id
    @user = user
    @account_user = account_user
  end

  def offered?
    store_blocker.nil? && Commerce::ActionRun::ORDER_ACTIONS.any? { |type| permitted?(type) }
  end

  def availability(order_id)
    store_blocker!
    snapshot = owned_snapshot(order_id)
    in_progress = in_progress?(order_id)
    {
      store: { id: @store.id, name: @store.name, provider: @store.provider },
      order: snapshot.order.as_json.except('customer'),
      version: snapshot.version,
      actions: Commerce::ActionRun::ORDER_ACTIONS.index_with { |type| capability(type, snapshot, in_progress) },
      last_run: runs(order_id).order(:created_at).last&.as_json
    }
  end

  # Returns the run: a new one (queued), or the one this idempotency key already made.
  def request(action_type, order_id:, version:, idempotency_key:, params:)
    raise Commerce::Error, 'INVALID_REQUEST' unless Commerce::ActionRun::ORDER_ACTIONS.include?(action_type)
    raise Pundit::NotAuthorizedError unless permitted?(action_type)
    raise Commerce::Error, 'INVALID_REQUEST' unless valid_request?(order_id, version, idempotency_key)

    values = normalize(action_type, params)
    digest = digest(action_type, order_id, values)
    throttle!(order_id)
    run = Commerce::StoreLock.with('commerce_action', "#{@store.id}:#{order_id}", wait: 3) do
      existing = Commerce::ActionRun.find_by(idempotency_key: idempotency_key)
      next replay(existing, digest) if existing

      store_blocker!
      raise Commerce::Error, 'ACTION_IN_PROGRESS' if in_progress?(order_id)

      create_run(action_type, order_id, idempotency_key, digest, values.merge('version' => version))
    end
    accepted(run) if run.previously_new_record?
    run
  end

  # The order, read from the store now, provided it is one of the linked customer's orders there.
  def owned_snapshot(order_id)
    ensure_owned!(order_id)
    provider.action_snapshot(order_id).tap do |snapshot|
      raise Commerce::Error.new('INVALID_RESPONSE', reason: 'other_order') unless snapshot.order.external_order_id == order_id
    end
  rescue Commerce::Error => e
    Commerce::StoreConnection.new(account: @store.account, user: nil).credentials_rejected(@store) if e.code == 'AUTH_INVALID'
    raise
  end

  # Steps 1-4: why no action of this store is possible now, or nil.
  def store_blocker(opt_in: true)
    return 'unsupported' unless provider.class.supports_actions?
    return 'actions_disabled' unless Commerce::Switches.actions_enabled?
    return 'provider_actions_disabled' unless Commerce::Switches.provider_actions_enabled?(@store.provider)
    return 'store_actions_off' if opt_in && @store.settings['order_actions'] != true

    provider.write_access_problem
  end

  def store_blocker!(opt_in: true)
    reason = store_blocker(opt_in: opt_in)
    raise Commerce::Error.new(STORE_ERRORS.fetch(reason, 'ACTION_UNAVAILABLE'), reason: reason) if reason
  end

  def permitted?(action_type)
    Commerce::ActionPolicy.new({ user: @user, account: @store.account, account_user: @account_user }, action_type).perform?
  end

  def provider
    @provider ||= Commerce::Providers.for(@store)
  end

  private

  def capability(action_type, snapshot, in_progress)
    offered = snapshot.capabilities[action_type]
    return { available: false, reason: 'unsupported' } if offered.nil?
    return { available: false, reason: 'permission_denied' } unless permitted?(action_type)
    return { available: false, reason: 'action_in_progress' } if in_progress

    offered
  end

  # Among the linked customer's latest OWNERSHIP_WINDOW orders, as the store lists them now.
  def ensure_owned!(order_id)
    raise Commerce::Error, 'NOT_FOUND' unless order_id.to_s.match?(ORDER_ID)

    link = @store.customer_links.not_suppressed.find_by(contact_id: @contact_id)
    raise Commerce::Error, 'NOT_FOUND' if link.nil?

    orders = provider.list_customer_orders(link.external_customer_id, limit: OWNERSHIP_WINDOW)
    raise Commerce::Error, 'NOT_FOUND' unless orders.any? { |order| order.external_order_id == order_id }
  end

  def create_run(action_type, order_id, idempotency_key, digest, metadata)
    Commerce::ActionRun.create!(
      account_id: @store.account_id, store: @store, contact_id: @contact_id, conversation_id: @conversation_id, requested_by: @user,
      provider: @store.provider, action_type: action_type, external_resource_id: order_id, idempotency_key: idempotency_key,
      request_digest: digest, metadata: metadata
    )
  end

  def runs(order_id)
    Commerce::ActionRun.order_actions.where(commerce_store_id: @store.id, external_resource_id: order_id)
  end

  # An action still being sent, or whose result is still being reconciled, blocks every other action on the order. One
  # whose reconciliation ran out is no longer blocking: the order read now is what the agent decides on.
  def in_progress?(order_id)
    runs(order_id).unresolved.where("COALESCE(commerce_action_runs.metadata->>'reconcile', '') <> 'exhausted'").exists?
  end

  def valid_request?(order_id, version, idempotency_key)
    order_id.to_s.match?(ORDER_ID) && version.to_s.match?(VERSION) && idempotency_key.to_s.start_with?('commerce-action:') &&
      idempotency_key.to_s.match?(Commerce::ActionRun::KEY_FORMAT)
  end

  # Only the documented values of each action are accepted.
  def normalize(action_type, params)
    case action_type
    when 'update_order_status' then { 'target_status' => allowed(params[:target_status], TARGET_STATUSES) }
    when 'cancel_order' then { 'reason' => allowed(params[:reason], CANCEL_REASONS), 'restock' => boolean(params.fetch(:restock, true)) }
    when 'refund_full', 'refund_partial'
      { 'amount' => amount(params[:amount]), 'currency' => allowed(params[:currency], nil, CURRENCY),
        'reason' => allowed(params[:reason], REFUND_REASONS) }
    else {}
    end
  end

  def allowed(value, list, format = nil)
    return value if value.is_a?(String) && (list ? list.include?(value) : value.match?(format))

    raise Commerce::Error, 'INVALID_REQUEST'
  end

  def boolean(value)
    return value if [true, false].include?(value)

    raise Commerce::Error, 'INVALID_REQUEST'
  end

  def amount(value)
    raise Commerce::Error, 'INVALID_AMOUNT' unless value.is_a?(String) && value.match?(AMOUNT) && BigDecimal(value).positive?

    value
  end

  def digest(action_type, order_id, values)
    Digest::SHA256.hexdigest([@store.account_id, @store.id, order_id, action_type, values.sort].to_json)
  end

  # The same key again: the run it made, never a second action. A key reused for a different request is refused.
  def replay(run, digest)
    raise Commerce::Error, 'IDEMPOTENCY_CONFLICT' unless run.account_id == @store.account_id && run.request_digest == digest

    Commerce::Metrics.event('commerce.action.replayed', provider: run.provider, store_id: run.commerce_store_id, run_id: run.id)
    run
  end

  def throttle!(order_id)
    { user: "USER::#{@user.id}", store: "STORE::#{@store.id}", order: "STORE::#{@store.id}::ORDER::#{order_id}" }.each do |scope, suffix|
      limit, period = RATE_LIMITS.fetch(scope)
      key = "COMMERCE::ACTION_RATE::ACCOUNT::#{@store.account_id}::#{suffix}"
      count = Redis::Alfred.incr(key)
      Redis::Alfred.expire(key, period.to_i) if count == 1
      raise Commerce::Error.new('RATE_LIMITED', reason: [Redis::Alfred.ttl(key).to_i, 1].max.to_s) if count > limit
    end
  end

  def accepted(run)
    Commerce::AuditTrail.record('commerce.action.requested', auditable: run, user: @user, changes: run.audit_fields)
    Commerce::Metrics.event('commerce.action.requested', provider: run.provider, store_id: run.commerce_store_id, action: run.action_type,
                                                         run_id: run.id)
    Commerce::ActionJob.perform_later(run.id)
  end
end
