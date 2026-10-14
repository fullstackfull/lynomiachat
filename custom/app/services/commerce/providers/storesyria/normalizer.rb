# Store Syria's vocabulary -> Lynomia's canonical one.
#
# WHY THERE IS SO MUCH TABLE HERE. Store Syria has no enum, no PHP constant and no database check
# constraint for either status. `orders.delivered_status` is a plain nullable-default-0 integer
# whose meaning lives in repeated if/match ladders, and `orders.payment_status` is free text
# written by ~52 gateway controllers in at least ten spellings ('success', 'succeeded',
# 'Succeeded', 'Paid', ...). Every value below was read out of that source rather than guessed,
# and anything unrecognised becomes 'other'/'unknown' rather than being forced into a neighbour.
#
# THE RAW VALUE IS ALWAYS KEPT. Commerce::Order carries provider_status precisely so an agent can
# be shown what the store actually said when the canonical mapping is lossy -- 'Picked Up' and
# 'Confirmed' both canonicalise to `processing`, and a merchant who ships from a warehouse cares
# about the difference.
class Commerce::Providers::Storesyria::Normalizer
  # orders.delivered_status, read from Order::order_status_change and the three display ladders.
  STATUS = {
    0 => 'pending',
    1 => 'delivered',
    2 => 'cancelled',
    3 => 'refunded',    # Return; the sub-state lives in return_status and is reported raw
    4 => 'processing',  # Confirmed
    5 => 'processing',  # Picked Up -- not 'shipped': it has not left the store
    6 => 'shipped',
    7 => 'pending',     # Partially Paid (PartialPayments module)
    8 => 'pending'      # Pre Order
  }.freeze

  # Store Syria canonicalises payment status on its side with
  # OrderFinancialService::normalizePaymentStatus, so the contract sends one of these six and
  # this map is the last line of defence rather than the ten-spelling problem itself.
  PAYMENT = {
    'paid' => 'paid',
    'unpaid' => 'unpaid',
    'pending' => 'unpaid',
    'partially_paid' => 'partially_paid',
    'refunded' => 'refunded',
    'cancelled' => 'unknown'
  }.freeze

  # There is NO separate shipping status column in Store Syria: fulfilment is folded into
  # delivered_status, with picked_date / shipped_date / delivery_date as the timestamps. A
  # shipment is therefore reported only for the states where one demonstrably exists.
  SHIPMENT = { 5 => 'pending', 6 => 'in_transit', 1 => 'delivered', 3 => 'returned' }.freeze

  def initialize(provider, store)
    @provider = provider
    @store = store
  end

  def customer(raw)
    Commerce::Customer.new(
      external_id: raw.fetch('id').to_s,
      name: raw['name'].to_s,
      emails: Array(raw['emails']).filter_map { |e| e.to_s.strip.downcase.presence },
      phones: Array(raw['phones']).filter_map { |p| Commerce::Phone.e164(p.to_s).presence },
      registered: !raw['guest']
    )
  rescue KeyError, TypeError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_customer')
  end

  def order(raw)
    delivered = raw['delivered_status'].to_i
    external_id = raw.fetch('id').to_s

    Commerce::Order.new(
      provider: 'storesyria', external_order_id: external_id,
      # product_order_id is the number a shopper and an agent both recognise; it falls back to the
      # id because the column is nullable and historical rows can be missing it.
      order_number: raw['number'].to_s.presence || external_id,
      items: items(raw['items']), item_count: raw['item_count']&.to_i, customer: raw['customer_id'].to_s.presence,
      admin_order_url: @provider.admin_order_url(external_id), customer_order_url: nil,
      **money(raw), **statuses(raw, delivered), **timestamps(raw), **fulfilment(raw, delivered)
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_order')
  end

  def cart(raw)
    Commerce::AbandonedCart.new(
      provider: 'storesyria', store_id: @store.id, external_cart_id: raw.fetch('id').to_s,
      items: Array(raw['items']).map { |item| { name: item['name'].to_s, quantity: item['quantity'].to_i } },
      # DELIBERATELY NIL. Store Syria has no durable cart token, so there is no link that restores
      # a basket; Commerce::RecoveryUrl would refuse a fabricated one anyway, and a fabricated
      # checkout URL is a bearer credential for someone else's cart.
      recovery_url: nil, status: 'abandoned', recovered_at: nil, provider_metadata: {},
      **money(raw), **timestamps(raw), **contact(raw)
    )
  rescue KeyError, TypeError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_cart')
  end

  private

  def statuses(raw, delivered)
    { status: STATUS.fetch(delivered, 'other'),
      provider_status: raw['status_label'].to_s.presence || delivered.to_s,
      payment_status: PAYMENT.fetch(raw['payment_status'].to_s.downcase, 'unknown') }
  end

  def money(raw) = { currency: raw['currency'].to_s.presence, total: decimal(raw['total']) }

  def timestamps(raw) = { created_at: timestamp(raw['created_at']), updated_at: timestamp(raw['updated_at']) }

  def fulfilment(raw, delivered) = { shipping: shipping(raw), shipments: shipments(raw, delivered), tracking: tracking(raw) }

  def contact(raw)
    { customer_reference: raw['customer_id'].to_s.presence, email: raw['email'].to_s.presence, phone: raw['phone'].to_s.presence }
  end

  # Money stays a DECIMAL STRING all the way through. Store Syria stores order money as PHP
  # floats and cart prices as integers; turning either into a Ruby Float here would reintroduce
  # the rounding this vocabulary exists to avoid.
  def decimal(value)
    return nil if value.nil? || value.to_s.strip.empty?

    BigDecimal(value.to_s).to_s('F')
  rescue ArgumentError
    nil
  end

  def timestamp(value)
    return nil if value.blank?

    Time.parse(value.to_s).utc.iso8601
  rescue ArgumentError
    nil
  end

  def items(raw)
    Array(raw).map do |item|
      { name: item['name'].to_s, quantity: item['quantity'].to_i, total: decimal(item['total']) }
    end
  end

  def shipping(raw)
    method = raw.dig('shipping', 'method').to_s.presence
    return nil if method.nil? && raw.dig('shipping', 'total').nil?

    { method: method, total: decimal(raw.dig('shipping', 'total')), provider: nil, status: nil }
  end

  def shipments(raw, delivered)
    state = SHIPMENT[delivered]
    return [] if state.nil?

    [{
      provider: raw.dig('shipping', 'carrier').to_s.presence,
      status: state,
      provider_status: raw['status_label'].to_s.presence || delivered.to_s,
      type: nil,
      tracking_number: raw['tracking_number'].to_s.presence,
      tracking_url: nil
    }]
  end

  # Never guessed from a carrier name: only what the store actually sent.
  def tracking(raw)
    number = raw['tracking_number'].to_s.presence
    return nil if number.nil?

    { number: number, url: nil }
  end
end
