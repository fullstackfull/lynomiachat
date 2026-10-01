# Shopify order actions (docs/commerce/29-provider-action-capabilities.md §Shopify): Admin GraphQL API 2026-07 only, never
# REST, with a token that holds write_orders (granted only when an administrator reconnects the store for order actions;
# scopes are never widened silently).
#
#   cancel_order         orderCancel for an unpaid, unfulfilled order: restocked, refund: false, the customer not
#                        notified. An authorization is voided by Shopify. Shopify cancels in a Job: the run stays running
#                        until reading the order shows it cancelled
#   refund_full/partial  refundCreate of an amount through the order's single payment transaction (Shopify's suggested
#                        refund transaction and its parent), up to what Shopify says is refundable; split payments are not
#                        offered. Sent with Shopify's @idempotent directive and the run's key, which the refund note also
#                        carries for reconciliation
#   status, resend, shipping  unsupported: Shopify has no order status to set, and resending is not confirmed
#
# userErrors, top-level GraphQL errors and HTTP errors are failures (Shopify did not act), except an internal error or a
# 5xx, which are unknown: the order is then read again, never the mutation sent again.
class Commerce::Providers::Shopify::Actions
  UNPAID = %w[PENDING AUTHORIZED EXPIRED].freeze
  CANCEL_REASONS = { 'customer_request' => 'CUSTOMER', 'inventory' => 'INVENTORY', 'fraud' => 'FRAUD', 'payment_declined' => 'DECLINED',
                     'other' => 'OTHER' }.freeze
  FIELDS = <<~GRAPHQL.freeze
    refundable presentmentCurrencyCode
    totalRefundedSet { presentmentMoney { amount } }
    suggestedRefund(suggestFullRefund: true) {
      maximumRefundableSet { presentmentMoney { amount } }
      suggestedTransactions { kind gateway formattedGateway parentTransaction { id } maximumRefundableSet { presentmentMoney { amount } } }
    }
    refunds(first: 20) { id legacyResourceId note createdAt }
  GRAPHQL
  CANCEL = <<~GRAPHQL.freeze
    mutation LynomiaOrderCancel($orderId: ID!, $reason: OrderCancelReason!, $restock: Boolean!, $staffNote: String) {
      orderCancel(orderId: $orderId, reason: $reason, restock: $restock, refund: false, notifyCustomer: false, staffNote: $staffNote) {
        job { id done }
        orderCancelUserErrors { code field message }
        userErrors { field message }
      }
    }
  GRAPHQL
  # Shopify requires an idempotency key on refundCreate since 2026-04, given with the @idempotent directive (VERIFY on a
  # live store: the directive is in Shopify's docs, not in the schema introspection Lynomia was built against).
  REFUND = <<~GRAPHQL.freeze
    mutation LynomiaRefundCreate($input: RefundInput!, $idempotencyKey: String!) {
      refundCreate(input: $input) @idempotent(key: $idempotencyKey) {
        refund { id legacyResourceId }
        userErrors { field message }
      }
    }
  GRAPHQL
  JOB = 'query LynomiaJob($id: ID!) { job(id: $id) { id done } }'.freeze
  SETTLED_AFTER = 5.minutes

  def initialize(provider, store)
    @provider = provider
    @store = store
  end

  def snapshot(raw)
    refund = refund_capability(raw)
    Commerce::ActionSnapshot.new(order: @provider.normalize_order(raw), version: version(raw),
                                 capabilities: { 'cancel_order' => cancel_capability(raw), 'refund_full' => refund, 'refund_partial' => refund },
                                 facts: { 'order_gid' => raw.fetch('id'), 'currency' => raw['presentmentCurrencyCode'],
                                          'transaction' => transaction(raw) })
  end

  def cancel(snapshot, params, key)
    variables = { orderId: snapshot.facts.fetch('order_gid'), reason: CANCEL_REASONS.fetch(params.fetch('reason')),
                  restock: params.fetch('restock', true) != false, staffNote: "Lynomia #{key}" }
    answer(*@provider.mutate(CANCEL, variables), 'orderCancel') do |payload|
      errors = Array(payload['orderCancelUserErrors']) + Array(payload['userErrors'])
      next Commerce::ActionResult.failed('PROVIDER_REJECTED') if errors.any?

      job = payload['job']
      job.is_a?(Hash) && job['id'].present? ? Commerce::ActionResult.running(job['id']) : Commerce::ActionResult.unknown
    end
  end

  def refund(snapshot, params, key)
    transaction = snapshot.facts.fetch('transaction')
    input = { orderId: snapshot.facts.fetch('order_gid'), currency: snapshot.facts.fetch('currency'), notify: false, note: "Lynomia #{key}",
              transactions: [{ orderId: snapshot.facts.fetch('order_gid'), amount: params.fetch('amount'), gateway: transaction.fetch('gateway'),
                               kind: 'REFUND', parentId: transaction.fetch('parent_id') }] }
    answer(*@provider.mutate(REFUND, { input: input, idempotencyKey: key }), 'refundCreate') do |payload|
      next Commerce::ActionResult.failed('PROVIDER_REJECTED') if Array(payload['userErrors']).any?

      reference = payload.dig('refund', 'legacyResourceId') if payload['refund'].is_a?(Hash)
      reference.present? ? Commerce::ActionResult.succeeded(reference) : Commerce::ActionResult.unknown
    end
  end

  # Read-only: the order (cancelled, its refunds and their notes) and the cancellation Job.
  def reconcile(run, snapshot, raw)
    case run.action_type
    when 'cancel_order' then reconcile_cancel(run, snapshot)
    when 'refund_full', 'refund_partial' then reconcile_refund(run, raw)
    else Commerce::ActionResult.unknown('NOT_RECONCILABLE')
    end
  end

  private

  def cancel_capability(raw)
    return unavailable('already_cancelled') if raw['cancelledAt'].present?
    return unavailable('paid_refund_first') unless UNPAID.include?(raw['displayFinancialStatus'].to_s)
    return unavailable('order_state') unless raw['displayFulfillmentStatus'] == 'UNFULFILLED'

    { available: true, restocks: true, refunds: false }
  end

  def refund_capability(raw)
    return unavailable('not_paid') unless raw['refundable'] == true

    suggested = refund_transactions(raw)
    return unavailable('multiple_payments') unless suggested.one?

    maximum = [money(raw.dig('suggestedRefund', 'maximumRefundableSet')), money(suggested.first['maximumRefundableSet'])].compact.min
    return unavailable('nothing_refundable') unless maximum&.positive?

    { available: true, max_amount: Commerce::Amount.format(maximum, like: raw.dig('currentTotalPriceSet', 'presentmentMoney', 'amount')),
      currency: raw['presentmentCurrencyCode'], mode: 'gateway', gateway: suggested.first['formattedGateway'].presence }.compact
  end

  def refund_transactions(raw)
    Array(raw.dig('suggestedRefund', 'suggestedTransactions')).select do |suggestion|
      suggestion['kind'] == 'SUGGESTED_REFUND' && suggestion['gateway'].present? && suggestion.dig('parentTransaction', 'id').present?
    end
  end

  def transaction(raw)
    suggestion = refund_transactions(raw).first
    suggestion && { 'gateway' => suggestion['gateway'], 'parent_id' => suggestion.dig('parentTransaction', 'id') }
  end

  # What Shopify's answer proves. HTTP 200 is not success: top-level errors mean the mutation did not run (an internal
  # error may have), and a missing payload is unknown.
  def answer(status, body, mutation)
    return http_failure(status) unless status == 200
    return graphql_failure(Array(body['errors'])) if body.is_a?(Hash) && body['errors'].present?

    payload = body.dig('data', mutation) if body.is_a?(Hash) && body['data'].is_a?(Hash)
    payload.is_a?(Hash) ? yield(payload) : Commerce::ActionResult.unknown
  end

  def http_failure(status)
    case status
    when 401 then Commerce::ActionResult.failed('AUTH_INVALID')
    when 429 then Commerce::ActionResult.failed('RATE_LIMITED')
    when 400..499 then Commerce::ActionResult.failed('PROVIDER_REJECTED')
    else Commerce::ActionResult.unknown
    end
  end

  def graphql_failure(errors)
    codes = errors.map { |error| error.is_a?(Hash) ? error.dig('extensions', 'code') : nil }
    return Commerce::ActionResult.unknown if codes.include?('INTERNAL_SERVER_ERROR')
    return Commerce::ActionResult.failed('RATE_LIMITED') if codes.include?('THROTTLED')
    return missing_scope if codes.include?('ACCESS_DENIED')

    Commerce::ActionResult.failed('PROVIDER_REJECTED')
  end

  def missing_scope
    @store.update!(metadata: @store.reload.metadata.merge('write_access' => 'missing_scope'))
    Commerce::ActionResult.failed('WRITE_ACCESS_DENIED')
  end

  def reconcile_cancel(run, snapshot)
    return Commerce::ActionResult.succeeded if snapshot.order.status == 'cancelled'

    job = @provider.query_job(run.provider_request_id) if run.provider_request_id.present?
    done = job.is_a?(Hash) && job['done'] == true
    done || (run.provider_request_id.blank? && settled?(run)) ? Commerce::ActionResult.failed('NOT_APPLIED') : Commerce::ActionResult.unknown
  end

  def reconcile_refund(run, raw)
    refunds = Array(raw['refunds'])
    ours = refunds.find { |refund| refund['note'].to_s.include?(run.idempotency_key) }
    return Commerce::ActionResult.succeeded(ours['legacyResourceId']) if ours
    return Commerce::ActionResult.failed('NOT_APPLIED') if settled?(run) && refunds.none? { |refund| since_send?(refund, run) }

    Commerce::ActionResult.unknown
  end

  def since_send?(refund, run)
    created = refund['createdAt'].presence && Time.iso8601(refund['createdAt'])
    created.nil? || created > run.started_at - 1.minute
  end

  def settled?(run) = run.started_at.present? && run.started_at < SETTLED_AFTER.ago

  def money(set)
    amount = set.is_a?(Hash) ? set.dig('presentmentMoney', 'amount') : nil
    amount.present? ? BigDecimal(amount.to_s) : nil
  end

  def version(raw)
    material = [raw['cancelledAt'], raw['displayFinancialStatus'], raw['displayFulfillmentStatus'],
                raw.dig('currentTotalPriceSet', 'presentmentMoney'), raw.dig('totalRefundedSet', 'presentmentMoney', 'amount'),
                Array(raw['refunds']).pluck('id')]
    Digest::SHA256.hexdigest(material.to_json).first(32)
  end

  def unavailable(reason) = { available: false, reason: reason }
end
