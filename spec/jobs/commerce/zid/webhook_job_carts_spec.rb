require 'rails_helper'

# P6 Stage B: a Zid abandoned-cart delivery, from the existing endpoint to the durable row and the one Automation
# event (docs/commerce-production/06-cart-transition-design.md).
RSpec.describe Commerce::Zid::WebhookJob do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, :zid, account: account) }
  let(:now) { Time.zone.parse('2026-10-06T12:00:00Z') }

  def cart_body(event, overrides = {})
    { 'event' => event, 'id' => 'zc-2002', 'cart_id' => 'ignored-1', 'session_id' => 'ignored-2',
      'phase' => 'shipping_method', 'created_at' => now.iso8601, 'updated_at' => now.iso8601,
      'customer_id' => '91', 'cart_total' => '99.00', 'currency_code' => 'SAR', 'products_count' => 2,
      'url' => 'https://zid-store.zid.store/checkout/secret-token' }.merge(overrides)
  end

  def perform(body)
    described_class.perform_now(store.id, Commerce::WebhookQueue.send(:encryptor, 'zid')
                                                                .encrypt_and_sign(body.to_json, purpose: 'commerce_zid_webhook'))
  end

  around do |example|
    with_modified_env(COMMERCE_ALLOW_PRE_UAT_PROVIDERS: 'true', ZID_RECOVERY_ENABLED: 'true') { example.run }
  end

  it 'subscribes to both official cart events and nothing invented' do
    expect(Commerce::Zid::Webhooks::EVENTS).to include('abandoned_cart.created', 'abandoned_cart.completed')
    expect(Commerce::Providers::Zid::CartEvents::EVENTS).to contain_exactly('abandoned_cart.created', 'abandoned_cart.completed')
  end

  it 'records the durable lifecycle from a created delivery' do
    expect { perform(cart_body('abandoned_cart.created')) }.to change(Commerce::Cart, :count).by(1)

    expect(Commerce::Cart.sole).to have_attributes(provider_cart_id: 'zc-2002', state: 'abandoned', item_count: 2)
  end

  it 'does not store the checkout URL the delivery carried' do
    perform(cart_body('abandoned_cart.created'))

    expect(Commerce::Cart.sole.attributes.values.map(&:to_s).join(' ')).not_to include('secret-token')
  end

  it 'treats a redelivery of the same body as one cart and one state' do
    perform(cart_body('abandoned_cart.created'))
    perform(cart_body('abandoned_cart.created'))

    expect(Commerce::Cart.count).to eq(1)
    expect(Commerce::Cart.sole.state).to eq('abandoned')
  end

  it 'routes an order delivery to the order path, untouched' do
    allow(Commerce::Realtime).to receive(:order_event)

    perform({ 'id' => '5001', 'customer' => { 'id' => '91' } })

    expect(Commerce::Realtime).to have_received(:order_event)
    expect(Commerce::Cart.count).to eq(0)
  end

  it 'reports a cart delivery it cannot place rather than guessing' do
    allow(Rails.logger).to receive(:error)

    expect(Rails.logger).to receive(:error).with(a_string_including('[COMMERCE CART] event=unusable_zid_cart_delivery'))
    expect { perform(cart_body('abandoned_cart.created').except('id')) }.not_to change(Commerce::Cart, :count)
  end

  describe 'the Automation event' do
    let(:contact) { create(:contact, account: account) }

    before do
      account.enable_features!('lynomia_commerce')
      create(:commerce_customer_link, account: account, store: store, contact: contact, external_customer_id: '91')
      create(:conversation, account: account, contact: contact)
    end

    it 'exposes commerce_cart_abandoned as a real trigger, and no recovered trigger' do
      expect(Automation::CommerceEvents::CART_EVENTS).to contain_exactly('commerce_cart_abandoned')
      expect(Automation::CommerceEvents::EVENTS).not_to include('commerce_cart_recovered')
      expect(Automation::CommerceEvents).to be_event('commerce_cart_abandoned')
    end

    it 'dispatches once for a genuine transition, and not again for a redelivery' do
      create(:automation_rule, account: account, event_name: 'commerce_cart_abandoned',
                               actions: [{ action_name: 'add_label', action_params: ['abandoned'] }])
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      perform(cart_body('abandoned_cart.created'))
      perform(cart_body('abandoned_cart.created'))

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('commerce.cart_abandoned', anything, anything).once
    end

    it 'does not dispatch on completion' do
      create(:automation_rule, account: account, event_name: 'commerce_cart_abandoned',
                               actions: [{ action_name: 'add_label', action_params: ['abandoned'] }])
      perform(cart_body('abandoned_cart.created'))
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      perform(cart_body('abandoned_cart.completed', 'phase' => 'completed', 'order_id' => '900',
                                                    'updated_at' => (now + 10.minutes).iso8601))

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with('commerce.cart_abandoned', anything, anything)
    end

    it 'carries no checkout URL or customer contact detail in the event payload' do
      perform(cart_body('abandoned_cart.created'))
      context = Automation::CommerceEvents.send(:cart_context, Commerce::Cart.sole)

      expect(context.keys).to contain_exactly(:id, :provider_cart_id, :phase, :currency, :total, :item_count, :abandoned_at)
    end
  end
end
