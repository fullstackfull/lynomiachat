# What changed between two reads of one customer link's visible orders, in Commerce's normalized vocabulary
# (docs/automation/04-commerce-triggers.md). Provider webhooks only say "this customer changed"; the normalized orders a
# new read returns are the only provider-neutral truth, so Lynomia Automation's Commerce triggers come from here.
#
# A state per visible order: { 's' status, 'p' payment status, 'h' shipment statuses, 'c' created at }, keyed by a hash
# of the store and order id (never the order itself). No previous state (the link's first read, or the first after
# deploy) is a baseline: nothing is emitted. Then, per order:
#
#   commerce_order_created    a new order newer than every order of the previous read (not an older one entering the
#                             visible window)
#   commerce_order_updated    an order of both reads whose status, payment status or shipments changed
#   commerce_order_paid       payment status became paid
#   commerce_order_shipped    status became shipped
#   commerce_order_delivered  status became delivered
#   commerce_order_cancelled  status became cancelled
#   commerce_order_refunded   status became refunded, or payment status refunded / partially refunded
#
# A new order emits created plus the facts already true of it (a card order is created and paid).
module Commerce::OrderTransitions
  Transition = Data.define(:event, :key, :order)

  FACTS = {
    'commerce_order_paid' => ->(state) { state['p'] == 'paid' },
    'commerce_order_shipped' => ->(state) { state['s'] == 'shipped' },
    'commerce_order_delivered' => ->(state) { state['s'] == 'delivered' },
    'commerce_order_cancelled' => ->(state) { state['s'] == 'cancelled' },
    'commerce_order_refunded' => ->(state) { state['s'] == 'refunded' || %w[refunded partially_refunded].include?(state['p']) }
  }.freeze
  EVENTS = (%w[commerce_order_created commerce_order_updated] + FACTS.keys).freeze

  def self.states(store_id, orders)
    orders.to_h do |order|
      shipments = Array(order['shipments']).filter_map { |shipment| shipment['status'] }.sort
      [key(store_id, order), { 's' => order['status'], 'p' => order['payment_status'], 'h' => shipments, 'c' => order['created_at'] }]
    end
  end

  def self.between(previous, current, store_id, orders)
    return [] if previous.nil?

    by_key = orders.index_by { |order| key(store_id, order) }
    newest = previous.values.filter_map { |state| time(state['c']) }.max
    current.flat_map do |key, state|
      events_for(previous[key], state, newest).map { |event| Transition.new(event: event, key: key, order: summary(by_key[key])) }
    end
  end

  def self.events_for(before, state, newest)
    if before.nil?
      return [] if newest && !(time(state['c']) && time(state['c']) > newest)

      return ['commerce_order_created', *facts_became_true({}, state)]
    end

    changed = before.slice('s', 'p', 'h') != state.slice('s', 'p', 'h')
    [*('commerce_order_updated' if changed), *facts_became_true(before, state)]
  end

  def self.facts_became_true(before, state) = FACTS.filter_map { |event, fact| event if fact.call(state) && !fact.call(before) }

  # What an automation webhook may carry: the order's number and normalized states, nothing personal.
  def self.summary(order)
    { 'number' => order['order_number'], 'status' => order['status'], 'payment_status' => order['payment_status'],
      'shipment_statuses' => Array(order['shipments']).filter_map { |shipment| shipment['status'] } }
  end

  def self.key(store_id, order) = Digest::SHA256.hexdigest("#{store_id}:#{order['external_order_id']}")[0, 24]

  def self.time(value)
    value.present? ? Time.zone.parse(value.to_s) : nil
  rescue ArgumentError
    nil
  end

  private_class_method :events_for, :facts_became_true, :summary, :time
end
