# Sends one requested order action to the store (Commerce::ActionJob), at most once, and settles runs whose answer was
# lost (Commerce::ActionReconcileJob). docs/commerce/28-commerce-actions-architecture.md §execution.
#
#   1. claims the run: pending → running in one UPDATE, so two workers never both send it
#   2. checks again what the request was accepted on: switches, opt-in, credentials, the requester's permission now
#   3. reads the order from the store again (ownership included); stops with ORDER_CHANGED when its version is not the one
#      the agent confirmed, and with ACTION_UNAVAILABLE when its state no longer allows the action
#   4. checks the amount: a refund is never above what the store says is refundable now, nor in another currency
#   5. sends it once. A lost answer marks the run unknown: it is never sent again, only reconciled by reading the store
#      (#reconcile, at RECONCILE_DELAYS). A worker that dies while sending is caught by the stall check.
# After a success the customer's cached orders are marked outdated and read again, and the account's agents are told
# (Commerce::Realtime): what the panel shows afterwards is the store's order, never an optimistic guess.
class Commerce::ActionExecutor
  STALL_CHECK = 2.minutes
  RECONCILE_DELAYS = [30.seconds, 2.minutes, 10.minutes].freeze
  METRICS = { 'succeeded' => 'commerce.action.success', 'failed' => 'commerce.action.failure' }.freeze

  def initialize(run)
    @run = run
  end

  def call
    return unless claim

    Commerce::ActionReconcileJob.set(wait: STALL_CHECK).perform_later(@run.id, true)
    execute
  end

  # Once after each send: a run still sending, without a store reference, means its worker died while sending it.
  def check_stall
    unknown!('UNKNOWN_OUTCOME') if @run.running? && @run.provider_request_id.nil?
  end

  # Read-only: decides from the order in the store whether a run whose answer was lost took effect.
  def reconcile
    return unless @run.unknown? || @run.running?

    attempts = @run.metadata['reconcile_attempts'].to_i + 1
    @run.update!(metadata: @run.metadata.merge('reconcile_attempts' => attempts))
    result = read_back
    return finish(result, reconciled: true) if %w[succeeded failed].include?(result.status)

    attempts < RECONCILE_DELAYS.size ? schedule_reconcile(attempts) : exhausted!
  end

  private

  # Row-locked, so two workers holding the same run never both send it.
  def claim
    @run.with_lock do
      next false unless @run.pending?

      @run.update!(status: :running, started_at: Time.current)
    end
  end

  def execute
    actions = order_actions
    snapshot = checked_snapshot(actions)
    finish(actions.provider.perform_action(@run.action_type, snapshot, params, @run.idempotency_key))
  rescue Commerce::Error => e
    e.reason == 'unknown_outcome' ? unknown!('UNKNOWN_OUTCOME') : fail!(e.code)
  end

  def order_actions
    account_user = AccountUser.find_by(account_id: @run.account_id, user_id: @run.requested_by_id)
    raise Commerce::Error, 'PERMISSION_DENIED' if account_user.nil?
    raise Commerce::Error, 'NOT_FOUND' unless store&.active? && Commerce::Providers.enabled?(store.provider)

    Commerce::OrderActions.new(store: store, contact_id: @run.contact_id, user: account_user.user, account_user: account_user).tap do |actions|
      raise Commerce::Error, 'PERMISSION_DENIED' unless actions.permitted?(@run.action_type)

      actions.store_blocker!
    end
  end

  def checked_snapshot(actions)
    snapshot = actions.owned_snapshot(@run.external_resource_id)
    remember(order_number: snapshot.order.order_number, from_status: snapshot.order.status)
    raise Commerce::Error, 'ORDER_CHANGED' unless snapshot.version == @run.metadata['version']

    capability = snapshot.capabilities[@run.action_type]
    raise Commerce::Error.new('ACTION_UNAVAILABLE', reason: capability&.dig(:reason) || 'unsupported') unless capability&.dig(:available)

    check_params!(capability)
    remember(mode: capability[:mode])
    snapshot
  end

  def remember(**values)
    @run.update!(metadata: @run.metadata.merge(values.stringify_keys.compact))
  end

  def check_params!(capability)
    case @run.action_type
    when 'update_order_status'
      raise Commerce::Error.new('ACTION_UNAVAILABLE', reason: 'target_status') unless Array(capability[:targets]).include?(params['target_status'])
    when 'refund_full', 'refund_partial' then check_amount!(capability)
    end
  end

  def check_amount!(capability)
    amount = params['amount']
    maximum = capability.fetch(:max_amount).to_s
    problem = if params['currency'] != capability.fetch(:currency) then 'currency'
              elsif amount.split('.', 2)[1].to_s.length > maximum.split('.', 2)[1].to_s.length then 'precision'
              elsif BigDecimal(amount) > BigDecimal(maximum) then 'above_refundable'
              elsif @run.action_type == 'refund_full' && BigDecimal(amount) != BigDecimal(maximum) then 'not_full'
              end
    raise Commerce::Error.new('INVALID_AMOUNT', reason: problem) if problem
  end

  def params
    @run.metadata.slice('target_status', 'reason', 'restock', 'amount', 'currency')
  end

  def finish(result, reconciled: false)
    case result.status
    when 'succeeded' then succeed(result, reconciled)
    when 'failed' then fail!(reconciled ? 'NOT_APPLIED' : result.message_code, reconciled: reconciled)
    when 'running'
      @run.update!(provider_request_id: result.provider_reference)
      schedule_reconcile(0)
    else unknown!(result.message_code)
    end
  end

  def succeed(result, reconciled)
    @run.update!(status: :succeeded, completed_at: Time.current, error_code: nil,
                 provider_request_id: result.provider_reference || @run.provider_request_id,
                 metadata: @run.metadata.merge('result' => order_state).compact)
    refresh_customer
    record('succeeded', reconciled)
  end

  def fail!(code, reconciled: false)
    @run.update!(status: :failed, completed_at: Time.current, error_code: code)
    record('failed', reconciled)
  end

  def unknown!(code)
    @run.update!(status: :unknown, error_code: code)
    Commerce::Metrics.event('commerce.action.unknown', **metric_fields)
    schedule_reconcile(@run.metadata['reconcile_attempts'].to_i)
  end

  # Reconciliation ran out: the run stays unknown and stops blocking the order; the agent checks the store.
  def exhausted!
    @run.update!(status: :unknown, metadata: @run.metadata.merge('reconcile' => 'exhausted'))
    record('unresolved', true)
  end

  def read_back
    return Commerce::ActionResult.unknown unless store&.active? && Commerce::Providers.enabled?(store.provider)

    provider = Commerce::Providers.for(store)
    provider.reconcile_action(@run, provider.action_snapshot(@run.external_resource_id))
  rescue Commerce::Error
    Commerce::ActionResult.unknown
  end

  def schedule_reconcile(attempts)
    Commerce::ActionReconcileJob.set(wait: RECONCILE_DELAYS.fetch(attempts)).perform_later(@run.id)
  end

  # The order's status afterwards, as the store reports it now; nil when it cannot be read (the refresh shows it later).
  def order_state
    order = Commerce::Providers.for(store).get_order(@run.external_resource_id)
    { 'status' => order.status, 'payment_status' => order.payment_status }
  rescue Commerce::Error
    nil
  end

  def refresh_customer
    link = store.customer_links.not_suppressed.find_by(contact_id: @run.contact_id)
    return if link.nil?

    Commerce::Cache.invalidate(store, :orders, link.external_customer_id)
    Commerce::Realtime.schedule_refresh(link)
  end

  # Audit and metric of an outcome: commerce.action.succeeded / failed, or commerce.action.reconciled with the outcome
  # (succeeded, failed, unresolved) when reconciliation settled it.
  def record(outcome, reconciled)
    event = reconciled ? 'commerce.action.reconciled' : "commerce.action.#{outcome}"
    Commerce::AuditTrail.record(event, auditable: @run, user: @run.requested_by, changes: @run.audit_fields.merge(outcome: outcome))
    Commerce::Metrics.event(reconciled ? event : METRICS.fetch(outcome), **metric_fields, outcome: outcome, code: @run.error_code)
  end

  def metric_fields = { provider: @run.provider, store_id: @run.commerce_store_id, action: @run.action_type, run_id: @run.id }

  def store = @run.store
end
