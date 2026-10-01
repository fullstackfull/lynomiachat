require 'rails_helper'

# Provider-neutral order changes between two reads (docs/automation/04-commerce-triggers.md).
RSpec.describe Commerce::OrderTransitions do
  let(:order) do
    lambda do |id, status, payment, created_at, shipments = []|
      { 'external_order_id' => id, 'order_number' => "N#{id}", 'status' => status, 'payment_status' => payment,
        'created_at' => created_at, 'shipments' => shipments.map { |shipment| { 'status' => shipment } } }
    end
  end
  let(:first_read) do
    [order.call('10', 'processing', 'unpaid', '2026-09-20T10:00:00Z'), order.call('9', 'completed', 'paid', '2026-09-01T10:00:00Z')]
  end

  def changes(previous_orders, current_orders)
    previous = previous_orders && described_class.states(4, previous_orders)
    described_class.between(previous, described_class.states(4, current_orders), 4, current_orders)
                   .map { |transition| [transition.event, transition.order['number']] }
  end

  it 'emits nothing for a first read: it is the baseline' do
    expect(changes(nil, first_read)).to be_empty
  end

  it 'emits nothing when nothing changed' do
    expect(changes(first_read, first_read)).to be_empty
  end

  it 'emits created for a new order, with the facts already true of it' do
    new_paid = order.call('11', 'processing', 'paid', '2026-09-28T10:00:00Z')

    expect(changes(first_read, [new_paid, *first_read])).to contain_exactly(%w[commerce_order_created N11], %w[commerce_order_paid N11])
    expect(changes([], [new_paid])).to include(%w[commerce_order_created N11])
  end

  it 'does not call an older order entering the visible window a new one' do
    older = order.call('5', 'completed', 'paid', '2026-07-01T10:00:00Z')

    expect(changes(first_read, [first_read.first, older])).to be_empty
  end

  it 'emits updated and each fact that became true, once' do
    paid = [order.call('10', 'processing', 'paid', '2026-09-20T10:00:00Z'), first_read.last]
    shipped = [order.call('10', 'shipped', 'paid', '2026-09-20T10:00:00Z', ['in_transit']), first_read.last]
    delivered = [order.call('10', 'delivered', 'paid', '2026-09-20T10:00:00Z', ['delivered']), first_read.last]

    expect(changes(first_read, paid)).to contain_exactly(%w[commerce_order_updated N10], %w[commerce_order_paid N10])
    expect(changes(paid, shipped)).to contain_exactly(%w[commerce_order_updated N10], %w[commerce_order_shipped N10])
    expect(changes(shipped, delivered)).to contain_exactly(%w[commerce_order_updated N10], %w[commerce_order_delivered N10])
    expect(changes(delivered, delivered)).to be_empty
  end

  it 'emits cancelled and refunded' do
    cancelled = [order.call('10', 'cancelled', 'unpaid', '2026-09-20T10:00:00Z'), first_read.last]
    refunded = [first_read.first, order.call('9', 'completed', 'partially_refunded', '2026-09-01T10:00:00Z')]

    expect(changes(first_read, cancelled)).to include(%w[commerce_order_cancelled N10])
    expect(changes(first_read, refunded)).to contain_exactly(%w[commerce_order_updated N9], %w[commerce_order_refunded N9])
  end

  it 'keeps only hashed ids and normalized states, never order data' do
    state = described_class.states(4, first_read)

    expect(state.keys).to all(match(/\A\h{24}\z/))
    expect(state.values.first.keys).to contain_exactly('s', 'p', 'h', 'c')
  end
end
