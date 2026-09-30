# Maps Shopify Admin GraphQL customers and orders (2026-07) to Commerce::Customer / Commerce::Order
# (docs/commerce/19-shopify-graphql-provider.md). Anything malformed raises INVALID_RESPONSE instead of leaking a partial
# or raw payload.
#
# Status: a cancelled order (cancelledAt) is cancelled; otherwise displayFulfillmentStatus maps explicitly, and a
# fulfilled order whose shipments were all delivered is delivered. RESTOCKED, REQUEST_DECLINED and anything new is
# `other`. `closed` (archived) is the merchant's filing, not a stage, so it is not read.
# Payment status: only displayFinancialStatus. AUTHORIZED, VOIDED and EXPIRED have no neutral equivalent and are
# unknown; it is never inferred from the fulfillment or order status.
# Shipments: one per tracking number of each fulfillment, or one per fulfillment without tracking, with the fulfillment's
# carrier status; tracking links only when https. Amounts are in the currency the customer paid in (presentment money).
# Customers carry no name: the connector does not request names (protected customer data), only the default email and
# phone, which must match exactly.
class Commerce::Providers::Shopify::Normalizer
  STATUSES = {
    'UNFULFILLED' => 'processing', 'PARTIALLY_FULFILLED' => 'processing', 'IN_PROGRESS' => 'processing', 'PENDING_FULFILLMENT' => 'processing',
    'OPEN' => 'processing', 'SCHEDULED' => 'processing', 'ON_HOLD' => 'on_hold', 'FULFILLED' => 'shipped'
  }.freeze
  PAYMENT_STATUSES = {
    'PAID' => 'paid', 'PENDING' => 'unpaid', 'PARTIALLY_PAID' => 'partially_paid', 'PARTIALLY_REFUNDED' => 'partially_refunded',
    'REFUNDED' => 'refunded'
  }.freeze
  SHIPMENT_STATUSES = {
    'LABEL_PRINTED' => 'pending', 'LABEL_PURCHASED' => 'pending', 'CONFIRMED' => 'pending', 'SUBMITTED' => 'pending',
    'READY_FOR_PICKUP' => 'pending', 'CARRIER_PICKED_UP' => 'in_transit', 'IN_TRANSIT' => 'in_transit', 'DELAYED' => 'in_transit',
    'ATTEMPTED_DELIVERY' => 'in_transit', 'OUT_FOR_DELIVERY' => 'out_for_delivery', 'DELIVERED' => 'delivered', 'PICKED_UP' => 'delivered',
    'FAILURE' => 'failed', 'NOT_DELIVERED' => 'failed', 'CANCELED' => 'cancelled'
  }.freeze
  CUSTOMER_GID = %r{\Agid://shopify/Customer/(\d+)\z}

  def initialize(provider)
    @provider = provider
  end

  def order(raw)
    id = positive_id(raw.fetch('legacyResourceId'))
    shipments = raw.fetch('fulfillments').flat_map { |fulfillment| shipments(fulfillment) }
    Commerce::Order.new(
      provider: 'shopify', external_order_id: id.to_s, order_number: raw.fetch('name').to_s.delete_prefix('#'),
      status: status(raw, shipments), provider_status: raw.fetch('displayFulfillmentStatus').to_s.downcase,
      payment_status: PAYMENT_STATUSES.fetch(raw['displayFinancialStatus'].to_s, 'unknown'),
      customer: order_customer(raw['customer']),
      admin_order_url: @provider.admin_order_url(id), customer_order_url: nil, **details(raw), **fulfilment(shipments)
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_order')
  end

  def customer(raw)
    Commerce::Customer.new(
      external_id: customer_id(raw.fetch('id')), name: nil, emails: [email(raw.dig('defaultEmailAddress', 'emailAddress'))].compact,
      phones: [Commerce::Phone.e164(raw.dig('defaultPhoneNumber', 'phoneNumber'))].compact, registered: true
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_customer')
  end

  # A guest checkout with exactly this email: no Shopify customer on the order.
  def guest_order?(raw, email)
    raw['customer'].nil? && email(raw['email']) == email
  end

  private

  def status(raw, shipments)
    return 'cancelled' if raw['cancelledAt'].present?

    status = STATUSES.fetch(raw.fetch('displayFulfillmentStatus').to_s, 'other')
    delivered = shipments.reject { |shipment| shipment[:status] == 'cancelled' }
    status == 'shipped' && delivered.any? && delivered.all? { |shipment| shipment[:status] == 'delivered' } ? 'delivered' : status
  end

  def shipments(fulfillment)
    status = fulfillment.fetch('status') == 'CANCELLED' ? 'cancelled' : SHIPMENT_STATUSES.fetch(fulfillment['displayStatus'].to_s, 'other')
    base = { status: status, provider_status: fulfillment['displayStatus'].to_s.downcase, type: 'shipment' }
    tracking = fulfillment.fetch('trackingInfo')
    return [base.merge(provider: nil, tracking_number: nil, tracking_url: nil)] if tracking.empty?

    tracking.map do |info|
      base.merge(provider: info['company'].to_s.strip.presence, tracking_number: info['number'].to_s.strip.presence,
                 tracking_url: https(info['url']))
    end
  end

  # The order's main shipment is its first active one with a tracking number or link, else its first active one.
  def fulfilment(shipments)
    active = shipments.reject { |shipment| shipment[:status] == 'cancelled' }
    main = active.find { |shipment| tracking(shipment) } || active.first
    return { shipping: nil, shipments: shipments, tracking: nil } unless main

    { shipping: { method: main[:provider], total: nil, provider: main[:provider], status: main[:status] }, shipments: shipments,
      tracking: tracking(main) }
  end

  def tracking(shipment)
    { number: shipment[:tracking_number], url: shipment[:tracking_url] } if shipment[:tracking_number] || shipment[:tracking_url]
  end

  # Amounts, times and the order's first line items; item_count is the whole order's quantity.
  def details(raw)
    money = raw.fetch('currentTotalPriceSet').fetch('presentmentMoney')
    { currency: money.fetch('currencyCode').to_s, total: amount(money.fetch('amount')), created_at: time(raw.fetch('createdAt')),
      updated_at: time(raw.fetch('updatedAt')), items: items(raw.fetch('lineItems').fetch('nodes')),
      item_count: Integer(raw.fetch('subtotalLineItemsQuantity')) }
  end

  def items(nodes)
    nodes.map do |item|
      { name: item.fetch('name').to_s, quantity: Integer(item.fetch('quantity')),
        total: amount(item.fetch('discountedTotalSet').fetch('presentmentMoney').fetch('amount')) }
    end
  end

  # The order's Shopify customer, or nil for a guest checkout. No name: names are not requested.
  def order_customer(raw)
    { external_id: customer_id(raw.fetch('id')), name: nil } if raw
  end

  def customer_id(gid)
    gid.to_s[CUSTOMER_GID, 1] || raise(ArgumentError, 'unexpected customer id')
  end

  def email(value)
    value.to_s.strip.downcase.presence
  end

  def https(url)
    uri = URI.parse(url.to_s)
    url.to_s if uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    nil
  end

  def time(value)
    Time.iso8601(value.to_s).utc.iso8601
  end

  def amount(value)
    BigDecimal(value.to_s).to_s('F')
  end

  def positive_id(value)
    id = Integer(value.to_s, 10)
    raise ArgumentError, 'id must be positive' unless id.positive?

    id
  end
end
