# The provider-neutral order action core (Commerce::OrderActions, Commerce::ActionExecutor) against a provider whose store
# answers are stubbed per example: one linked customer with order 501 (100.00 SAR, paid, processing) in a WooCommerce
# store whose administrator turned order actions on. Real providers' actions have their own specs.
RSpec.shared_context 'with commerce order actions' do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:store) { create(:commerce_store, account: account, settings: { 'order_actions' => true }) }
  let(:contact) { create(:contact, account: account) }
  let(:link) { create(:commerce_customer_link, store: store, account: account, contact: contact, external_customer_id: '7') }
  let(:provider_class) do
    Class.new(Commerce::Providers::Base) do
      def self.supports_actions? = true

      def write_access_problem = nil
    end
  end
  let(:provider) { provider_class.new(store, credentials: {}) }
  let(:order) do
    Commerce::Order.new(
      provider: 'woocommerce', external_order_id: '501', order_number: '501', status: 'processing', provider_status: 'processing',
      payment_status: 'paid', currency: 'SAR', total: '100.00', created_at: '2026-09-30T10:00:00Z', updated_at: nil, items: [],
      item_count: 0, customer: { external_id: '7', name: 'Omar' }, shipping: nil, shipments: [], tracking: nil,
      admin_order_url: nil, customer_order_url: nil
    )
  end
  let(:version) { 'a1' * 8 }
  let(:capabilities) do
    {
      'refund_full' => { available: true, max_amount: '100.00', currency: 'SAR', mode: 'gateway' },
      'refund_partial' => { available: true, max_amount: '100.00', currency: 'SAR', mode: 'gateway' },
      'cancel_order' => { available: false, reason: 'paid_refund_first' },
      'update_order_status' => { available: true, targets: %w[completed on_hold] }
    }
  end
  let(:snapshot) { Commerce::ActionSnapshot.new(order: order, version: version, capabilities: capabilities, facts: {}) }
  let(:key) { "commerce-action:#{SecureRandom.uuid}" }

  before do
    link
    allow(Commerce::Providers).to receive(:for).and_return(provider)
    allow(provider).to receive(:list_customer_orders).and_return([order])
    allow(provider).to receive(:action_snapshot).and_return(snapshot)
    allow(provider).to receive(:get_order).and_return(order)
    Redis::Alfred.scan_each(match: 'COMMERCE::ACTION_RATE::*') { |redis_key| Redis::Alfred.delete(redis_key) }
  end
end
