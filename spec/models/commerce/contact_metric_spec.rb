require 'rails_helper'

RSpec.describe Commerce::ContactMetric do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, account: account) }
  let(:link) { create(:commerce_customer_link, store: store, external_customer_id: '7') }
  let(:orders) do
    [
      { 'status' => 'processing', 'payment_status' => 'paid', 'currency' => 'SAR', 'total' => '100.50', 'created_at' => '2026-09-20T10:00:00Z',
        'shipments' => [{ 'status' => 'in_transit' }] },
      { 'status' => 'completed', 'payment_status' => 'paid', 'currency' => 'USD', 'total' => '20.00', 'created_at' => '2026-08-01T10:00:00Z' },
      { 'status' => 'cancelled', 'payment_status' => 'unpaid', 'currency' => 'SAR', 'total' => '50.00', 'created_at' => '2026-09-25T10:00:00Z' }
    ]
  end
  let(:read) { ->(value, at) { Commerce::Cache::Result.new(value: value, fetched_at: at.utc.iso8601, stale: false, error: nil) } }

  it 'sums what one read returned the way Customer 360 does: visible, per currency, cancelled orders are no purchase' do
    described_class.record(link, read.call(orders, Time.current))

    expect(described_class.sole).to have_attributes(
      account_id: account.id, orders_count: 3, active_orders_count: 1, spend: { 'SAR' => '100.5', 'USD' => '20.0' },
      order_statuses: %w[cancelled completed processing], payment_statuses: %w[paid unpaid], shipment_statuses: %w[in_transit]
    )
    expect(described_class.sole.last_purchase_at).to eq(Time.zone.parse('2026-09-20T10:00:00Z'))
  end

  it 'records a known empty history as zero, and never lets an older read replace a newer one' do
    described_class.record(link, read.call([], 1.minute.ago))
    described_class.record(link, read.call(orders, 2.minutes.ago))

    expect(described_class.sole).to have_attributes(orders_count: 0, spend: {}, last_purchase_at: nil)
  end

  it 'is dropped when its link is removed or points to another customer, and goes with the link' do
    described_class.record(link, read.call(orders, Time.current))
    link.update!(confirmed_by: create(:user, account: account))
    expect(described_class.count).to eq(1)

    link.update!(match_source: :suppressed)
    expect(described_class.count).to eq(0)

    described_class.record(link, read.call(orders, Time.current))
    link.update!(match_source: :manual, external_customer_id: '8')
    expect(described_class.count).to eq(0)

    described_class.record(link, read.call(orders, Time.current))
    store.customer_links.delete_all
    expect(described_class.count).to eq(0)
  end
end
