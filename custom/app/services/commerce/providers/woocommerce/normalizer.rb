# Maps WooCommerce REST v3 JSON to Commerce::Order / Commerce::Customer. Anything malformed raises
# INVALID_RESPONSE instead of leaking a partial or raw payload.
#
# Payment status (WooCommerce has no payment-status field, so it is derived, in this order):
#   refunded            status "refunded", or refunds covering the whole total
#   partially_refunded  any refund (a refund is itself evidence the order was paid)
#   paid                status processing/completed (WooCommerce's paid statuses) AND date_paid_gmt set; WooCommerce
#                       sets date_paid when a gateway confirms payment or the merchant moves the order to its paid status
#   unpaid              status "pending" (pending payment)
#   failed              status "failed"
#   unknown             everything else: on-hold (awaiting bank transfer), cash on delivery not yet completed,
#                       cancelled, custom statuses, missing data
#
# Shipping is the shipping line method titles. WooCommerce core has no tracking, so tracking is always nil: plugin
# metadata (Shipment Tracking, courier plugins) is not read.
class Commerce::Providers::Woocommerce::Normalizer
  STATUSES = {
    'pending' => 'pending', 'processing' => 'processing', 'on-hold' => 'on_hold', 'completed' => 'completed',
    'cancelled' => 'cancelled', 'refunded' => 'refunded', 'failed' => 'failed', 'checkout-draft' => 'draft'
  }.freeze
  PAID_STATUSES = %w[processing completed].freeze
  UNPAID_STATUSES = { 'pending' => 'unpaid', 'failed' => 'failed' }.freeze

  def initialize(provider)
    @provider = provider
  end

  def order(raw)
    status = raw.fetch('status').to_s
    items = items(raw)
    Commerce::Order.new(
      provider: 'woocommerce', external_order_id: positive_id(raw.fetch('id')).to_s, order_number: raw.fetch('number').to_s,
      status: STATUSES.fetch(status, 'other'), provider_status: status, payment_status: payment_status(raw, status),
      currency: raw.fetch('currency').to_s, total: amount(raw.fetch('total')), items: items, item_count: items.sum { |item| item[:quantity] },
      customer: order_customer(raw), shipping: shipping(raw), tracking: nil, customer_order_url: nil,
      admin_order_url: @provider.admin_order_url(raw.fetch('id')), **timestamps(raw)
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_order')
  end

  def customer(raw)
    billing = raw['billing'] || {}
    shipping = raw['shipping'] || {}
    Commerce::Customer.new(
      external_id: positive_id(raw.fetch('id')).to_s,
      name: name(raw['first_name'], raw['last_name']) || name(billing['first_name'], billing['last_name']),
      emails: emails(raw['email'], billing['email']),
      phones: phones([billing['phone'], billing['country']], [shipping['phone'], shipping['country'].presence || billing['country']]),
      registered: true
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_customer')
  end

  def customer_from_order(raw, guest_id)
    customer_id = Integer(raw.fetch('customer_id').to_s, 10)
    billing = raw.fetch('billing')
    Commerce::Customer.new(
      external_id: customer_id.positive? ? customer_id.to_s : guest_id, name: name(billing['first_name'], billing['last_name']),
      emails: emails(billing['email']), phones: order_phones(raw), registered: customer_id.positive?
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_order')
  end

  # Every normalized email and E.164 phone on an order, for exact re-checks after a broad search.
  def order_identifiers(raw)
    emails((raw['billing'] || {})['email']) + order_phones(raw)
  end

  private

  def payment_status(raw, status)
    refunded = refunded_amount(raw)
    return 'refunded' if status == 'refunded' || (refunded.positive? && refunded >= BigDecimal(raw.fetch('total').to_s))
    return 'partially_refunded' if refunded.positive?
    return 'paid' if PAID_STATUSES.include?(status) && raw['date_paid_gmt'].present?

    UNPAID_STATUSES.fetch(status, 'unknown')
  end

  def refunded_amount(raw)
    Array(raw['refunds']).sum { |refund| BigDecimal(refund.fetch('total').to_s).abs }
  end

  def items(raw)
    raw.fetch('line_items').map do |item|
      { name: item.fetch('name').to_s, quantity: Integer(item.fetch('quantity').to_s, 10), total: amount(item.fetch('total')) }
    end
  end

  def shipping(raw)
    lines = raw.fetch('shipping_lines')
    return if lines.empty?

    { method: lines.filter_map { |line| line['method_title'].to_s.strip.presence }.join(', ').presence, total: amount(raw.fetch('shipping_total')) }
  end

  def order_customer(raw)
    customer_id = Integer(raw.fetch('customer_id').to_s, 10)
    billing = raw['billing'] || {}
    { external_id: customer_id.positive? ? customer_id.to_s : nil, name: name(billing['first_name'], billing['last_name']) }
  end

  def order_phones(raw)
    billing = raw['billing'] || {}
    shipping = raw['shipping'] || {}
    phones([billing['phone'], billing['country']], [shipping['phone'], shipping['country'].presence || billing['country']])
  end

  def phones(*pairs)
    pairs.filter_map { |phone, country| Commerce::Phone.e164(phone, country) }.uniq
  end

  def emails(*values)
    values.filter_map { |value| value.to_s.strip.downcase.presence }.uniq
  end

  def name(first, last)
    [first, last].map { |part| part.to_s.strip }.compact_blank.join(' ').presence
  end

  def amount(value)
    BigDecimal(value.to_s)
    value.to_s
  end

  def timestamps(raw)
    { created_at: time(raw.fetch('date_created_gmt')), updated_at: time(raw['date_modified_gmt']) }
  end

  def time(value)
    return if value.blank?

    Time.iso8601("#{value}Z").utc.iso8601
  end

  def positive_id(value)
    id = Integer(value.to_s, 10)
    raise ArgumentError, 'id must be positive' unless id.positive?

    id
  end
end
