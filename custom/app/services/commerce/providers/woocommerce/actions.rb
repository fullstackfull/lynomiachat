# WooCommerce order actions (docs/commerce/29-provider-action-capabilities.md §WooCommerce): REST API v3 with a Read/Write
# key the store's administrator chose to use. Every capability is judged from the order as the store returns it now.
#
#   update_order_status  allow-list only: processing → completed or on-hold, on-hold → processing. Never trash, never a
#                        plugin's status
#   cancel_order         pending or on-hold (unpaid) orders only. WooCommerce restores the stock and refunds nothing; a
#                        paid order is refunded first
#   refund_full/partial  paid orders (processing or completed with a payment date), up to what is still refundable: the
#                        total minus every refund the store reports. Through the payment gateway when it supports
#                        refunds (money goes back to the customer), else recorded only (no money moves). Amount-only:
#                        no line items, nothing restocked
#   resend_invoice       WooCommerce's "Order details" email to the order's billing email (paid or on-hold orders)
#   resend_payment_link  the same email for an order still waiting for payment: it carries the store's payment link
#   update_shipping      unsupported (it would mean editing an address)
#
# Each refund carries the run's idempotency key as order refund meta (lynomia_action_key): that is how a lost answer is
# reconciled. WooCommerce has no idempotency of its own, so nothing is ever sent twice.
class Commerce::Providers::Woocommerce::Actions
  API_PATH = Commerce::Providers::Woocommerce::API_PATH
  STATUS_TARGETS = { 'processing' => %w[completed on_hold], 'on-hold' => %w[processing] }.freeze
  WOO_STATUSES = { 'completed' => 'completed', 'on_hold' => 'on-hold', 'processing' => 'processing', 'cancelled' => 'cancelled' }.freeze
  CANCELLABLE = %w[pending on-hold].freeze
  PAID = %w[processing completed].freeze
  INVOICE_STATUSES = %w[processing completed on-hold].freeze
  AWAITING_PAYMENT = %w[pending failed].freeze
  REFUND_REASONS = {
    'customer_request' => 'Customer request', 'duplicate' => 'Duplicate order', 'damaged' => 'Damaged item',
    'not_received' => 'Item not received', 'other' => 'Other'
  }.freeze
  META_KEY = 'lynomia_action_key'.freeze
  REJECTED = { 400 => 'PROVIDER_REJECTED', 403 => 'PROVIDER_REJECTED', 404 => 'NOT_FOUND', 409 => 'PROVIDER_REJECTED',
               422 => 'PROVIDER_REJECTED' }.freeze
  REFUND_NOT_CREATED = 'woocommerce_rest_cannot_create_order_refund'.freeze
  GATEWAY_ID = /\A[\w-]{1,64}\z/
  # A request WordPress was still running when its answer was lost has finished by then (PHP's execution limits): only
  # after this long does "nothing changed" prove an action was not applied.
  SETTLED_AFTER = 5.minutes

  def initialize(provider, http, store)
    @provider = provider
    @http = http
    @store = store
  end

  def snapshot(external_order_id)
    raw = order(external_order_id)
    order = @provider.normalize_order(raw)
    Commerce::ActionSnapshot.new(order: order, version: version(raw), capabilities: capabilities(raw), facts: {})
  end

  def perform(action_type, snapshot, params, idempotency_key)
    id = snapshot.order.external_order_id
    case action_type
    when 'update_order_status' then change_status(id, WOO_STATUSES.fetch(params.fetch('target_status')))
    when 'cancel_order' then change_status(id, 'cancelled')
    when 'refund_full', 'refund_partial' then refund(id, snapshot.capabilities.fetch(action_type).fetch(:mode), params, idempotency_key)
    when 'resend_invoice', 'resend_payment_link'
      answer(*@http.write_json(:post, "#{API_PATH}/orders/#{id}/actions/send_order_details", {})) { succeeded }
    else raise ArgumentError, "unsupported action #{action_type}"
    end
  end

  # Read-only: the order's status, or the store's refunds and the key each one carries.
  def reconcile(run, snapshot)
    case run.action_type
    when 'refund_full', 'refund_partial' then reconcile_refund(run)
    when 'update_order_status', 'cancel_order'
      target = run.action_type == 'cancel_order' ? 'cancelled' : run.metadata['target_status']
      return Commerce::ActionResult.succeeded if snapshot.order.status == target
      return Commerce::ActionResult.failed('NOT_APPLIED') if snapshot.order.status == run.metadata['from_status'] && settled?(run)

      Commerce::ActionResult.unknown
    else Commerce::ActionResult.unknown('NOT_RECONCILABLE')
    end
  end

  private

  def capabilities(raw)
    status = raw.fetch('status').to_s
    refund = refund_capability(raw, status)
    {
      'update_order_status' => STATUS_TARGETS.key?(status) ? { available: true, targets: STATUS_TARGETS[status] } : unavailable('order_state'),
      'cancel_order' => cancel_capability(status),
      'refund_full' => refund, 'refund_partial' => refund,
      'resend_invoice' => email_capability(raw, INVOICE_STATUSES.include?(status)),
      'resend_payment_link' => email_capability(raw, AWAITING_PAYMENT.include?(status) && raw['needs_payment'] != false)
    }
  end

  def cancel_capability(status)
    return { available: true, restocks: true, refunds: false } if CANCELLABLE.include?(status)
    return unavailable('already_cancelled') if status == 'cancelled'

    unavailable(PAID.include?(status) ? 'paid_refund_first' : 'order_state')
  end

  def refund_capability(raw, status)
    return unavailable('not_paid') unless PAID.include?(status) && raw['date_paid_gmt'].present?

    remaining = BigDecimal(raw.fetch('total').to_s) - refunded(raw)
    return unavailable('nothing_refundable') unless remaining.positive?

    gateway = gateway_refunds?(raw['payment_method'])
    { available: true, max_amount: Commerce::Amount.format(remaining, like: raw.fetch('total')), currency: raw.fetch('currency').to_s,
      mode: gateway ? 'gateway' : 'manual', gateway: gateway ? raw['payment_method_title'].to_s.presence : nil }.compact
  end

  def email_capability(raw, status_allows)
    return unavailable('order_state') unless status_allows
    return unavailable('no_email') if raw.dig('billing', 'email').blank?

    { available: true }
  end

  # Whether the order's payment gateway can send money back. Unknown (no gateway, not readable) means no: the refund is
  # then only recorded.
  def gateway_refunds?(payment_method)
    return false unless payment_method.to_s.match?(GATEWAY_ID)

    gateway = @http.get_json("#{API_PATH}/payment_gateways/#{payment_method}")
    gateway.is_a?(Hash) && gateway['enabled'] == true && Array(gateway['method_supports']).include?('refunds')
  rescue Commerce::Error => e
    raise if %w[AUTH_INVALID TIMEOUT STORE_UNAVAILABLE].include?(e.code)

    false
  end

  def change_status(id, status)
    answer(*@http.write_json(:put, "#{API_PATH}/orders/#{id}", { status: status })) do |body|
      body.is_a?(Hash) && body['status'] == status ? succeeded(id) : Commerce::ActionResult.unknown
    end
  end

  def refund(id, mode, params, idempotency_key)
    body = { amount: params.fetch('amount'), reason: "Lynomia: #{REFUND_REASONS.fetch(params.fetch('reason'))}", api_refund: mode == 'gateway',
             api_restock: false, meta_data: [{ key: META_KEY, value: idempotency_key }] }
    answer(*@http.write_json(:post, "#{API_PATH}/orders/#{id}/refunds", body)) do |refund|
      refund.is_a?(Hash) && refund['id'].present? ? succeeded(refund['id']) : Commerce::ActionResult.unknown
    end
  end

  # What the store's answer proves. A 500 is unknown (it may come from a proxy while WordPress still runs) except
  # WooCommerce's own "refund not created", which it answers only after removing the refund it could not complete.
  def answer(status, body)
    return yield(body) if status.between?(200, 201)
    return write_denied if status == 401
    return Commerce::ActionResult.failed(REJECTED[status]) if REJECTED.key?(status)
    return Commerce::ActionResult.failed('REFUND_DECLINED') if status == 500 && body.is_a?(Hash) && body['code'] == REFUND_NOT_CREATED

    Commerce::ActionResult.unknown
  end

  # The key read the order a moment ago but may not write it: it is a Read key after all, and the store says so from now on.
  def write_denied
    @store.update!(metadata: @store.reload.metadata.merge('write_access' => 'read_only_key'))
    Commerce::ActionResult.failed('WRITE_ACCESS_DENIED')
  end

  def reconcile_refund(run)
    refunds = refunds(run.external_resource_id)
    ours = refunds.find { |refund| Array(refund['meta_data']).any? { |meta| meta.values_at('key', 'value') == [META_KEY, run.idempotency_key] } }
    return succeeded(ours['id']) if ours
    return Commerce::ActionResult.failed('NOT_APPLIED') if settled?(run) && refunds.none? { |refund| since_send?(refund, run) }

    Commerce::ActionResult.unknown
  end

  def refunds(order_id)
    list = @http.get_json("#{API_PATH}/orders/#{Integer(order_id, 10)}/refunds", per_page: 100)
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless list.is_a?(Array) && list.all?(Hash)

    list
  end

  def settled?(run) = run.started_at.present? && run.started_at < SETTLED_AFTER.ago

  # A refund created after the action was sent (a minute of clock skew allowed) may be this one without its key yet.
  def since_send?(refund, run)
    created = refund['date_created_gmt'].presence && Time.iso8601("#{refund['date_created_gmt']}Z")
    created.nil? || created > run.started_at - 1.minute
  end

  def order(external_order_id)
    raw = @http.get_json("#{API_PATH}/orders/#{Integer(external_order_id.to_s, 10)}")
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless raw.is_a?(Hash)

    raw
  end

  # What the agent confirmed against: status, payment, totals and refunds. Notes or metadata changing do not count.
  def version(raw)
    material = [raw['status'], raw['currency'], raw['total'], raw['date_paid_gmt'], raw['payment_method'],
                Array(raw['refunds']).map { |refund| [refund['id'], refund['total']] }]
    Digest::SHA256.hexdigest(material.to_json).first(32)
  end

  def refunded(raw)
    Array(raw['refunds']).sum(BigDecimal(0)) { |refund| BigDecimal(refund.fetch('total').to_s).abs }
  end

  def unavailable(reason) = { available: false, reason: reason }

  def succeeded(reference = nil) = Commerce::ActionResult.succeeded(reference)
end
