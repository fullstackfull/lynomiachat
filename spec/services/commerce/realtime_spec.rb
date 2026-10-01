require 'rails_helper'

# The provider-neutral realtime core (docs/commerce/24-realtime-architecture.md): invalidation granularity, coalesced
# refreshes, the minimal ActionCable event, and the kill switch. The store's event parsing is a provider's; here it is
# given directly.
RSpec.describe Commerce::Realtime do
  include_context 'with commerce encryption'
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, account: account, base_url: 'https://shop.example.com', external_store_id: 'shop.example.com') }
  let(:other_store) { create(:commerce_store, account: account) }
  let(:contact) { create(:contact, account: account) }
  let!(:link) { create_link(store, contact, '7') }
  let(:provider) { Commerce::Providers.for(store) }
  let(:orders_api) { stub_request(:get, 'https://shop.example.com/wp-json/wc/v3/orders').with(query: hash_including('customer' => '7')) }
  let(:cache_key) { ->(target, kind, id) { "COMMERCE::V1::ACCOUNT::#{target.account_id}::STORE::#{target.id}::#{kind}::#{hmac(id)}" } }

  def create_link(target, owner, customer_id)
    Commerce::CustomerLink.create!(account: target.account, store: target, contact: owner, external_customer_id: customer_id,
                                   match_source: :verified_phone)
  end

  def hmac(id) = OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, id.to_s)

  def enqueued_refreshes = enqueued_jobs.select { |job| job['job_class'] == 'Commerce::RefreshJob' }

  def broadcasts
    enqueued_jobs.select { |job| job['job_class'] == 'ActionCableBroadcastJob' && job['arguments'][1] == 'commerce.customer.updated' }
  end

  def warm(target, kind, id)
    Redis::Alfred.setex(cache_key.call(target, kind, id), { value: [], fetched_at: Time.current.utc.iso8601 }.to_json, 1.day)
  end

  def event(customer_ids)
    allow(Commerce::Providers).to receive(:for).and_call_original
    allow(Commerce::Providers).to receive(:for).with(store).and_return(provider)
    allow(provider).to receive(:event_customer_ids).and_return(customer_ids)
    described_class.order_event(store, {})
  end

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('shop.example.com').and_return(['93.184.216.34'])
    [store, other_store].each { |target| Commerce::Cache.purge(target) }
    Redis::Alfred.scan_each(match: "COMMERCE::REFRESH::ACCOUNT::#{account.id}::*") { |key| Redis::Alfred.delete(key) }
    orders_api.to_return(status: 200, body: JSON.parse(file_fixture('commerce/woocommerce/orders.json').read).first(2).to_json)
  end

  describe '.order_event' do
    it 'drops only the named customer\'s cached orders and schedules one refresh for its linked contact' do
      warm(store, 'ORDERS', '7')
      warm(store, 'ORDERS', '8')
      warm(store, 'CANDIDATES', 'x')
      warm(other_store, 'ORDERS', '7')

      event(%w[7 7])

      expect(Redis::Alfred.exists?(cache_key.call(store, 'ORDERS', '7'))).to be(false)
      [cache_key.call(store, 'ORDERS', '8'), cache_key.call(store, 'CANDIDATES', 'x'), cache_key.call(other_store, 'ORDERS', '7')].each do |key|
        expect(Redis::Alfred.exists?(key)).to be(true)
      end
      expect(enqueued_refreshes.size).to eq(1)
      expect(enqueued_refreshes.first).to include('arguments' => [link.id], 'scheduled_at' => be_present)
    end

    it 'drops every customer\'s cached orders of the store when the event names none, and refreshes nobody' do
      warm(store, 'ORDERS', '7')
      warm(store, 'ORDERS', '8')
      warm(store, 'CANDIDATES', 'x')
      warm(other_store, 'ORDERS', '7')

      event([])

      expect(%w[7 8].map { |id| Redis::Alfred.exists?(cache_key.call(store, 'ORDERS', id)) }).to eq([false, false])
      expect(Redis::Alfred.exists?(cache_key.call(store, 'CANDIDATES', 'x'))).to be(true)
      expect(Redis::Alfred.exists?(cache_key.call(other_store, 'ORDERS', '7'))).to be(true)
      expect(enqueued_refreshes).to be_empty
    end

    it 'coalesces a burst of events for one customer into one refresh' do
      allow(Commerce::Metrics).to receive(:event).and_call_original

      20.times { event(['7']) }

      expect(enqueued_refreshes.size).to eq(1)
      expect(Commerce::Metrics).to have_received(:event).with('commerce.refresh.coalesced', anything).exactly(19).times
    end

    it 'refreshes nothing for a customer nobody is linked to, nor another store\'s link with the same customer id' do
      create_link(other_store, create(:contact, account: account), '9')

      event(['9'])

      expect(enqueued_refreshes).to be_empty
    end

    it 'only drops cached orders when realtime is switched off, a store is disabled, or its provider is switched off' do
      with_modified_env(COMMERCE_REALTIME_ENABLED: 'false') { event(['7']) }
      store.update!(status: :disabled)
      event(['7'])

      expect(enqueued_refreshes).to be_empty
      expect(broadcasts).to be_empty
    end
  end

  describe '.refresh' do
    it 'reads the orders again, caches them and sends the account a minimal event' do
      described_class.refresh(link)

      expect(orders_api).to have_been_requested.once
      expect(Commerce::Cache.fetch(store, :orders, '7') { raise 'not cached' }.value.size).to eq(2)
      expect(broadcasts.size).to eq(1)
      tokens, event_name, data = broadcasts.first['arguments']
      expect(tokens).to eq(["account_#{account.id}"])
      expect(event_name).to eq('commerce.customer.updated')
      expect(data.except('_aj_symbol_keys').keys).to contain_exactly('account_id', 'contact_id', 'store_id', 'updated_at')
      expect(data).to include('account_id' => account.id, 'contact_id' => contact.id, 'store_id' => store.id)
    end

    it 'runs once more when an event arrived during the refresh, and only once' do
      described_class.schedule_refresh(link)
      clear_enqueued_jobs
      stub_request(:get, 'https://shop.example.com/wp-json/wc/v3/orders').with(query: hash_including('customer' => '7')).to_return do
        2.times { event(['7']) }
        { status: 200, body: '[]' }
      end

      described_class.refresh(link)

      expect(enqueued_refreshes.size).to eq(1)
      expect(Redis::Alfred.exists?(cache_key.call(store, 'ORDERS', '7'))).to be(false)
    end

    it 'flags a store whose credentials are rejected, still tells the agents, and frees the customer for later events' do
      stub_request(:get, 'https://shop.example.com/wp-json/wc/v3/orders').with(query: hash_including('customer' => '7')).to_return(status: 401)

      expect { described_class.refresh(link) }.not_to raise_error

      expect(store.reload).to be_needs_reauth
      expect(broadcasts.size).to eq(1)
      event(['7'])
      expect(enqueued_refreshes).to be_empty
      store.update!(status: :active)
      event(['7'])
      expect(enqueued_refreshes.size).to eq(1)
    end

    it 'does not read a store whose provider is switched off, and still clears its lock' do
      allow(Commerce::Providers).to receive(:enabled?).and_return(false)

      described_class.refresh(link)

      expect(orders_api).not_to have_been_requested
      allow(Commerce::Providers).to receive(:enabled?).and_call_original
      event(['7'])
      expect(enqueued_refreshes.size).to eq(1)
    end
  end

  describe Commerce::RefreshJob do
    it 'refreshes a link and ignores one deleted meanwhile' do
      described_class.perform_now(link.id)
      expect(orders_api).to have_been_requested.once

      link.destroy!
      expect { described_class.perform_now(link.id) }.not_to raise_error
    end
  end
end
