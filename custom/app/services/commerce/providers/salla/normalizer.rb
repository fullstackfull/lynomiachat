# Maps Salla Merchant API JSON to Commerce::Order / Commerce::Customer. Anything malformed raises INVALID_RESPONSE
# instead of leaking a partial or raw payload.
#
# Status: `status.slug` (a merchant's custom status keeps the slug of the status it is based on).
# Payment status: only what Salla states explicitly. `is_pending_payment` or the payment_pending status mean unpaid;
# nothing else in an order says whether it was paid, so everything else is unknown. It is never inferred from an order
# status such as completed.
# Links: Salla admin links use an opaque id, so the admin link is the order's own `urls.admin`, kept only when it is
# https on Salla's merchant dashboard (s.salla.sa). Shipment tracking links are kept only for trackable shipments, and
# only when they are https.
class Commerce::Providers::Salla::Normalizer
  STATUSES = {
    'payment_pending' => 'pending', 'under_review' => 'on_hold', 'in_progress' => 'processing', 'completed' => 'completed',
    'shipped' => 'shipped', 'delivering' => 'shipped', 'delivered' => 'delivered', 'canceled' => 'cancelled', 'restored' => 'refunded'
  }.freeze
  SHIPMENT_STATUSES = {
    'creating' => 'pending', 'created' => 'pending', 'in_progress' => 'pending',
    'shipped' => 'in_transit', 'in_transit' => 'in_transit', 'received_at_final_hub' => 'in_transit',
    'to_be_reattempted' => 'in_transit', 'reattempted' => 'in_transit', 'delivering' => 'out_for_delivery',
    'delivered' => 'delivered', 'unable_to_deliver' => 'failed', 'lost' => 'failed', 'damaged' => 'failed',
    'cancelled' => 'cancelled', 'return_to_origin' => 'returned', 'return_in_progress' => 'returned'
  }.freeze
  ADMIN_HOST = 's.salla.sa'.freeze

  def order(raw)
    slug = raw.fetch('status').fetch('slug').to_s
    Commerce::Order.new(
      provider: 'salla', external_order_id: positive_id(raw.fetch('id')).to_s, order_number: raw.fetch('reference_id').to_s,
      status: STATUSES.fetch(slug, 'other'), provider_status: slug, payment_status: payment_status(raw, slug), **total(raw), **items(raw),
      customer: order_customer(raw['customer']), shipping: nil, shipments: [], tracking: nil, customer_order_url: nil,
      admin_order_url: admin_url(raw.dig('urls', 'admin')), created_at: time(raw.fetch('date')), updated_at: nil
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_order')
  end

  def customer(raw)
    Commerce::Customer.new(
      external_id: positive_id(raw.fetch('id')).to_s, name: name(raw['first_name'], raw['last_name']),
      emails: [raw['email'].to_s.strip.downcase.presence].compact, phones: [Commerce::Phone.e164("#{raw['mobile_code']}#{raw['mobile']}")].compact,
      registered: true
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_customer')
  end

  # { provider:, status:, provider_status:, type:, tracking_number:, tracking_url: } for a Shipments API record.
  def shipment(raw)
    status = raw['status'].is_a?(Hash) ? raw['status']['slug'].to_s : raw['status'].to_s
    {
      provider: raw['courier_name'].to_s.strip.presence, status: SHIPMENT_STATUSES.fetch(status, 'other'), provider_status: status,
      type: raw['type'].to_s, tracking_number: raw['tracking_number'].to_s.strip.presence,
      tracking_url: (raw['tracking_link'] if raw['trackable'] == true && https?(raw['tracking_link']))
    }
  rescue TypeError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_shipment')
  end

  # Every shipment is kept; the order's shipping and tracking are its first outgoing shipment (not a return) with a
  # tracking number or link, else its first outgoing shipment.
  def with_shipments(order, shipments)
    outgoing = shipments.reject { |shipment| shipment[:type] == 'return' }
    primary = outgoing.find { |shipment| tracked?(shipment) } || outgoing.first
    return order.with(shipments: shipments) if primary.nil?

    tracking = { number: primary[:tracking_number], url: primary[:tracking_url] } if tracked?(primary)
    carriers = outgoing.filter_map { |shipment| shipment[:provider] }.uniq.join(', ').presence
    order.with(shipments: shipments, tracking: tracking,
               shipping: { method: carriers, total: nil, provider: primary[:provider], status: primary[:status] })
  end

  private

  def payment_status(raw, slug)
    raw['is_pending_payment'] == true || slug == 'payment_pending' ? 'unpaid' : 'unknown'
  end

  def total(raw)
    total = raw.fetch('amounts').fetch('total')
    { currency: total.fetch('currency').to_s, total: amount(total.fetch('amount')) }
  end

  # item_count is nil when the order came without its items.
  def items(raw)
    return { items: [], item_count: nil } unless raw['items'].is_a?(Array)

    items = raw['items'].map do |item|
      total = item.dig('amounts', 'total', 'amount')
      { name: item.fetch('name').to_s, quantity: Integer(item.fetch('quantity').to_s, 10), total: total.nil? ? nil : amount(total) }
    end
    { items: items, item_count: items.sum { |item| item[:quantity] } }
  end

  def tracked?(shipment)
    shipment[:tracking_number].present? || shipment[:tracking_url].present?
  end

  def order_customer(raw)
    return if raw.nil?

    { external_id: raw['id'] ? positive_id(raw['id']).to_s : nil, name: name(raw['first_name'], raw['last_name']) }
  end

  def admin_url(url)
    uri = URI.parse(url.to_s)
    url if uri.is_a?(URI::HTTPS) && uri.host == ADMIN_HOST && uri.userinfo.nil?
  rescue URI::InvalidURIError
    nil
  end

  def https?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  # Salla dates: { date: "2026-09-28 14:03:11.000000", timezone: "Asia/Riyadh" }.
  def time(value)
    zone = ActiveSupport::TimeZone[value.fetch('timezone').to_s] || raise(ArgumentError, 'unknown time zone')
    zone.parse(value.fetch('date').to_s).utc.iso8601
  end

  def amount(value)
    BigDecimal(value.to_s)
    value.to_s
  end

  def name(first, last)
    [first, last].map { |part| part.to_s.strip }.compact_blank.join(' ').presence
  end

  def positive_id(value)
    id = Integer(value.to_s, 10)
    raise ArgumentError, 'id must be positive' unless id.positive?

    id
  end
end
