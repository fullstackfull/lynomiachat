# Maps Zid Merchant API orders (payload_type=default) to Commerce::Order / Commerce::Customer
# (docs/commerce/16-zid-provider.md). Anything malformed raises INVALID_RESPONSE instead of leaking a partial or raw
# payload.
#
# Status: `order_status.code`, compared lowercased (the orders API writes indelivery, webhook conditions inDelivery).
# Zid's six statuses map explicitly; new, preparing and ready are all "processing", since Zid keeps payment apart and
# "pending" means pending payment here. Anything else (reversed, a merchant or future status) is `other`.
# Payment status: only Zid's explicit `payment_status`: paid, pending (unpaid) and refunded. voided and anything else are
# unknown; it is never inferred from the order status.
# Identity: a marketplace order (is_marketplace_order) gives no customer, and a masked value ("J*** D***", "t***@…",
# "***00") is never an email or phone, so neither can match or be linked. Zid mobiles are international digits without
# "+" ("966500000006").
# Dates: Zid sends "YYYY-MM-DD HH:MM:SS" without a zone; they are read in the store's time zone from its Zid profile.
# Links: no admin link (Zid does not document one); tracking links only when https.
class Commerce::Providers::Zid::Normalizer
  STATUSES = {
    'new' => 'processing', 'preparing' => 'processing', 'ready' => 'processing', 'indelivery' => 'shipped', 'delivered' => 'delivered',
    'cancelled' => 'cancelled', 'canceled' => 'cancelled'
  }.freeze
  PAYMENT_STATUSES = { 'paid' => 'paid', 'pending' => 'unpaid', 'refunded' => 'refunded' }.freeze
  # Zid gives a shipment no status of its own that is documented; the order's own delivery statuses say where it is.
  SHIPMENT_STATUSES = { 'indelivery' => 'in_transit', 'delivered' => 'delivered' }.freeze
  DEFAULT_TIME_ZONE = 'Asia/Riyadh'.freeze

  def initialize(time_zone: nil)
    @zone = ActiveSupport::TimeZone[time_zone.to_s] || ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
  end

  def order(raw)
    code = raw.fetch('order_status').fetch('code').to_s.downcase
    id = positive_id(raw.fetch('id')).to_s
    Commerce::Order.new(
      provider: 'zid', external_order_id: id, order_number: id, status: STATUSES.fetch(code, 'other'), provider_status: code,
      payment_status: PAYMENT_STATUSES.fetch(raw['payment_status'].to_s, 'unknown'), currency: raw.fetch('currency_code').to_s,
      total: amount(raw.fetch('order_total')), customer: order_customer(raw['customer']), admin_order_url: nil, customer_order_url: nil,
      **items(raw), **fulfilment(raw['shipping'], code), **timestamps(raw)
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_order')
  end

  # The customer of an order, as a match candidate, or nil for a marketplace order or an order without a customer.
  def order_candidate(raw)
    customer(raw['customer']) unless raw['is_marketplace_order'] == true || raw['customer'].nil?
  end

  def customer(raw)
    Commerce::Customer.new(
      external_id: positive_id(raw.fetch('id')).to_s, name: raw['name'].to_s.strip.presence,
      emails: [email(raw['email'])].compact, phones: [phone(raw['mobile'])].compact, registered: true
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_customer')
  end

  private

  # { shipping:, shipments:, tracking: } from the order's shipping method, where Zid keeps its one shipment.
  def fulfilment(shipping, code)
    method = shipping['method'] if shipping.is_a?(Hash)
    return { shipping: nil, shipments: [], tracking: nil } unless method.is_a?(Hash)

    shipment = shipment(method, SHIPMENT_STATUSES.fetch(code, 'other'))
    { shipping: { method: method['name'].to_s.strip.presence, total: nil, provider: shipment&.dig(:provider), status: shipment&.dig(:status) },
      shipments: [shipment].compact, tracking: shipment && tracking(shipment) }
  end

  # The shipment's tracking number and link come from its tracking, else its waybill; links only when https.
  def shipment(method, status)
    sources = [method['tracking'], method['waybill']].grep(Hash)
    number = first_present(sources, 'number', 'tracking_number')
    url = sources.flat_map { |source| source.values_at('url', 'tracking_url') }.find { |candidate| https?(candidate) }
    provider = courier(method['courier'])
    return unless number || url || provider

    { provider: provider || method['name'].to_s.strip.presence, status: status, provider_status: provider_status(method, sources),
      type: 'shipment', tracking_number: number, tracking_url: url }
  end

  def provider_status(method, sources)
    (first_present(sources, 'status') || method['order_shipping_status']).to_s
  end

  def first_present(sources, *keys)
    sources.flat_map { |source| source.values_at(*keys) }.map { |value| value.to_s.strip }.find(&:present?)
  end

  def tracking(shipment)
    { number: shipment[:tracking_number], url: shipment[:tracking_url] } if shipment[:tracking_number] || shipment[:tracking_url]
  end

  # A courier is a name, or { name: { ar:, en: }, code:, logo: }.
  def courier(value)
    name = value.is_a?(Hash) ? value['name'] : value
    name = name['en'].presence || name['ar'] if name.is_a?(Hash)
    name.to_s.strip.presence
  end

  # item_count is nil when the order came without its products.
  def items(raw)
    return { items: [], item_count: nil } unless raw['products'].is_a?(Array)

    items = raw['products'].map do |product|
      { name: product.fetch('name').to_s, quantity: Integer(product.fetch('quantity').to_s, 10),
        total: product['total'].nil? ? nil : amount(product['total']) }
    end
    { items: items, item_count: items.sum { |item| item[:quantity] } }
  end

  def timestamps(raw)
    { created_at: time(raw.fetch('created_at')), updated_at: raw['updated_at'] && time(raw['updated_at']) }
  end

  def order_customer(raw)
    return if raw.nil?

    { external_id: positive_id(raw.fetch('id')).to_s, name: raw['name'].to_s.strip.presence }
  end

  def email(value)
    email = value.to_s.strip.downcase
    email if email.present? && email.exclude?('*')
  end

  def phone(value)
    number = value.to_s.strip
    return if number.include?('*')

    Commerce::Phone.e164(number.match?(/\A[1-9]\d{7,14}\z/) ? "+#{number}" : number)
  end

  def https?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  def time(value)
    (@zone.parse(value.to_s) || raise(ArgumentError, 'invalid time')).utc.iso8601
  end

  # "100.00000000000000" → "100.0": a decimal string in the order's currency.
  def amount(value)
    BigDecimal(value.to_s).to_s('F')
  end

  def positive_id(value)
    id = Integer(value.to_s, 10)
    raise ArgumentError, 'id must be positive' unless id.positive?

    id
  end
end
