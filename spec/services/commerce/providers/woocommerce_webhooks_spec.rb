require 'rails_helper'

# WooCommerce webhook registration and order events (docs/commerce/24-realtime-architecture.md §4).
RSpec.describe Commerce::Providers::Woocommerce do
  include_context 'with commerce encryption'
  include ActiveJob::TestHelper

  let(:store) { create(:commerce_store, base_url: 'https://shop.example.com', external_store_id: 'shop.example.com') }
  let(:api) { 'https://shop.example.com/wp-json/wc/v3' }
  let(:delivery_url) { "https://app.lynomia.test/webhooks/woocommerce/#{store.id}" }
  let(:provider) { Commerce::Providers.for(store) }
  let(:created) { [] }

  around { |example| with_modified_env(FRONTEND_URL: 'https://app.lynomia.test') { example.run } }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('shop.example.com').and_return(['93.184.216.34'])
    hooks = [{ id: 3, delivery_url: delivery_url }, { id: 4, delivery_url: 'https://other.example/hook' }]
    stub_request(:get, "#{api}/webhooks").with(query: hash_including({})).to_return(status: 200, body: hooks.to_json)
    stub_request(:delete, "#{api}/webhooks/3").with(query: { 'force' => 'true' }).to_return(status: 200, body: '{}')
    stub_request(:post, "#{api}/webhooks").to_return do |request|
      created << JSON.parse(request.body)
      { status: 201, body: { id: 40 + created.size }.to_json }
    end
  end

  describe '#register_webhooks' do
    it 'replaces Lynomia\'s webhooks with one per order topic, signed with a new secret saved encrypted first' do
      provider.register_webhooks

      expect(a_request(:delete, "#{api}/webhooks/3").with(query: { 'force' => 'true' })).to have_been_made.once
      expect(a_request(:delete, "#{api}/webhooks/4").with(query: hash_including({}))).not_to have_been_made
      expect(created.pluck('topic')).to eq(%w[order.created order.updated order.deleted])
      expect(created.pluck('delivery_url').uniq).to eq([delivery_url])
      secret = store.reload.credentials['webhook_secret']
      expect(secret).to match(/\A\h{64}\z/)
      expect(created.pluck('secret').uniq).to eq([secret])
      expect(store.metadata).to include('realtime' => include('status' => 'active', 'webhook_ids' => %w[41 42 43]), 'write_access' => 'granted')
    end

    it 'keeps the secret encrypted at rest and writes nothing but its own webhooks' do
      provider.register_webhooks

      expect(Commerce::Store.where(id: store.id).pick(Arel.sql('credentials::text'))).not_to include(store.reload.credentials['webhook_secret'])
      expect(a_request(:any, %r{/wp-json/wc/v3/(?!webhooks)}).with { |request| request.method != :get }).not_to have_been_made
    end

    it 'leaves a store with a Read key as it was: no webhook, no secret, realtime marked unavailable' do
      stub_request(:delete, "#{api}/webhooks/3").with(query: { 'force' => 'true' })
                                                .to_return(status: 401, body: { code: 'woocommerce_rest_authentication_error' }.to_json)
      stub_request(:post, "#{api}/webhooks").to_return(status: 401, body: { code: 'woocommerce_rest_authentication_error' }.to_json)

      expect { provider.register_webhooks }.not_to raise_error

      expect(store.reload.credentials).not_to have_key('webhook_secret')
      expect(store.metadata['realtime']).to include('status' => 'read_only_key', 'webhook_ids' => [])
      expect(store.metadata['write_access']).to eq('read_only_key')
      expect(store).to be_active
    end

    it 'raises when the key cannot read either, so the job reports it' do
      stub_request(:get, "#{api}/webhooks").with(query: hash_including({})).to_return(status: 401)

      expect { provider.register_webhooks }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('AUTH_INVALID') }
    end
  end

  describe '#release' do
    it 'deletes the webhooks Lynomia created, and tolerates ones already gone' do
      store.update!(metadata: { 'realtime' => { 'status' => 'active', 'webhook_ids' => %w[41 42] } })
      stub_request(:delete, "#{api}/webhooks/41").with(query: { 'force' => 'true' }).to_return(status: 200, body: '{}')
      stub_request(:delete, "#{api}/webhooks/42").with(query: { 'force' => 'true' }).to_return(status: 404, body: '{}')

      expect { provider.release }.not_to raise_error
      expect(a_request(:delete, "#{api}/webhooks/41").with(query: { 'force' => 'true' })).to have_been_made
    end
  end

  describe '#event_customer_ids' do
    let(:order) { JSON.parse(file_fixture('commerce/woocommerce/orders.json').read).first }

    it 'names a registered customer by id, and a guest by every identity the order carries' do
      expect(provider.event_customer_ids(order.merge('customer_id' => 12))).to eq(['12'])
      billing = order['billing'].merge('email' => ' Omar@Example.com ', 'phone' => '0551112233', 'country' => 'SA')
      guest = order.merge('customer_id' => 0, 'billing' => billing)
      expect(provider.event_customer_ids(guest)).to include('guest:omar@example.com', 'guest:+966551112233')
    end

    it 'names nobody for an event without a customer, or a malformed one' do
      expect(provider.event_customer_ids({ 'id' => 25 })).to eq([])
      expect(provider.event_customer_ids({ 'customer_id' => 'x' })).to eq([])
      expect(provider.event_customer_ids('not a hash')).to eq([])
    end
  end

  describe 'after a new authorization' do
    it 'registers the webhooks of a connected, re-keyed or re-enabled store' do
      connection = Commerce::StoreConnection.new(account: store.account, user: nil)
      allow(Commerce::Providers).to receive(:for).and_call_original
      allow(Commerce::Providers).to receive(:for).with(store, credentials: anything).and_return(instance_double(described_class, health: true))
      allow(Commerce::Providers).to receive(:for).with(store).and_return(instance_double(described_class, health: true))

      connection.rotate_credentials(store, { 'consumer_key' => 'ck_new', 'consumer_secret' => 'cs_new' })
      store.update!(status: :disabled)
      connection.enable(store)

      expect(enqueued_jobs.count { |job| job[:job] == Commerce::WebhookRegistrationJob && job[:args] == [store.id] }).to eq(2)
    end
  end
end
