# Zid order actions (docs/commerce/29-provider-action-capabilities.md §Zid). Only what Zid's official SDK confirms:
# `POST /v1/managers/store/orders/{id}/change-order-status` with `order_status`, answered with the updated `order`.
#
#   update_order_status  two steps of Zid's own order flow: ready → indelivery (shipped) and indelivery → delivered.
#                        Moving into "ready" needs a pickup location, which Lynomia does not choose, so it is not offered
#   cancel_order         unsupported: the status name differs between Zid's docs (cancelled, canceled); VERIFY
#   refunds              unsupported: Zid refunds through reverse orders (returns), not an order refund
#   resend, shipping     unsupported
#
# Zid publishes no list of granted scopes Lynomia can read: a status change Zid refuses with 403 marks the store as
# needing more permissions (write_access missing_scope) until it is re-authorized. Zid has no idempotency: nothing is
# ever sent twice, and a lost answer is settled by reading the order's status.
class Commerce::Providers::Zid::Actions
  TARGETS = { 'ready' => { 'shipped' => 'indelivery' }, 'indelivery' => { 'delivered' => 'delivered' } }.freeze
  SETTLED_AFTER = 5.minutes
  REFUSED = { 400 => 'PROVIDER_REJECTED', 401 => 'AUTH_INVALID', 404 => 'NOT_FOUND', 409 => 'PROVIDER_REJECTED', 422 => 'PROVIDER_REJECTED',
              429 => 'RATE_LIMITED' }.freeze

  def initialize(provider, store)
    @provider = provider
    @store = store
  end

  def snapshot(raw)
    code = raw.fetch('order_status').fetch('code').to_s.downcase
    targets = TARGETS.fetch(code, {}).keys
    capability = targets.any? ? { available: true, targets: targets } : { available: false, reason: 'order_state' }
    Commerce::ActionSnapshot.new(order: @provider.normalize_order(raw), version: version(raw, code),
                                 capabilities: { 'update_order_status' => capability }, facts: { 'code' => code })
  end

  # [path, body] of the one request a status change sends.
  def request(snapshot, params)
    code = TARGETS.fetch(snapshot.facts.fetch('code')).fetch(params.fetch('target_status'))
    ["/managers/store/orders/#{Integer(snapshot.order.external_order_id, 10)}/change-order-status", { order_status: code }]
  end

  def answer(status, body, expected_code)
    return missing_scope if status == 403
    return Commerce::ActionResult.failed(REFUSED[status]) if REFUSED.key?(status)
    return Commerce::ActionResult.unknown unless status.between?(200, 201) && body.is_a?(Hash)

    body.dig('order', 'order_status', 'code').to_s.downcase == expected_code ? Commerce::ActionResult.succeeded : Commerce::ActionResult.unknown
  end

  def reconcile(run, snapshot)
    return Commerce::ActionResult.succeeded if snapshot.order.status == run.metadata['target_status']
    return Commerce::ActionResult.failed('NOT_APPLIED') if snapshot.order.status == run.metadata['from_status'] && settled?(run)

    Commerce::ActionResult.unknown
  end

  private

  def missing_scope
    @store.update!(metadata: @store.reload.metadata.merge('write_access' => 'missing_scope'))
    Commerce::ActionResult.failed('WRITE_ACCESS_DENIED')
  end

  def settled?(run) = run.started_at.present? && run.started_at < SETTLED_AFTER.ago

  def version(raw, code)
    Digest::SHA256.hexdigest([code, raw['payment_status'], raw['order_total'], raw['currency_code']].to_json).first(32)
  end
end
