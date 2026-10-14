require 'rails_helper'

# P3A. Store Syria as Lynomia's fifth commerce provider.
#
# The properties worth pinning are the ones that are invisible in a single file: that the
# provider is registered in BOTH lists (nothing reconciles them, and a provider in only one is
# constructible but unconnectable), that it never sends a store identifier of its own, and that
# Store Syria's statusless integers map into the canonical vocabulary rather than near it.
RSpec.describe Commerce::Providers::Storesyria do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:store) do
    create(:commerce_store, account: account, provider: 'storesyria',
                            external_store_id: 'storesyria.test:4', base_url: 'https://storesyria.test',
                            credentials: { 'commerce_token' => 'lsc_4_1_deadbeef' })
  end
  let(:provider) { described_class.new(store, credentials: store.credentials) }

  before { allow(Resolv).to receive(:getaddresses).with('storesyria.test').and_return(['93.184.216.70']) }

  def stub_store(body)
    stub_request(:get, 'https://storesyria.test/api/lynomia/commerce/v1/store')
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'registration' do
    # A provider in REGISTRY but not in Commerce::Store::PROVIDERS can be constructed and will
    # then fail model validation on every write. The two lists are independent in upstream and
    # this is the only thing keeping them honest.
    it 'is in both provider lists, which nothing else reconciles' do
      expect(Commerce::Providers::REGISTRY).to include('storesyria' => described_class.name)
      expect(Commerce::Store::PROVIDERS).to include('storesyria')
      expect(Commerce::Providers::REGISTRY.keys.sort).to eq(Commerce::Store::PROVIDERS.sort)
    end

    it 'is resolvable through the registry' do
      expect(Commerce::Providers.for(store)).to be_a(described_class)
    end

    it 'is off unless the installation turns it on' do
      expect(described_class.enabled?).to be(false)

      GlobalConfig.clear_cache
      create(:installation_config, name: 'STORESYRIA_ENABLED', value: true)
      GlobalConfig.clear_cache

      expect(described_class.enabled?).to be(true)
    end

    # Read-only. Writing to a merchant's orders from a chat window is a product decision nobody
    # has made, and the contract does not expose it.
    it 'declares no write capability' do
      expect(described_class.supports_actions?).to be(false)
      expect(described_class.registers_webhooks?).to be(false)
    end
  end

  describe 'identity and health' do
    it 'reports the identity the store returns' do
      stub_store({ external_store_id: 'storesyria.test:4', name: 'UAT Store' })

      expect(provider.store_identity).to eq(external_store_id: 'storesyria.test:4', name: 'UAT Store')
      expect(provider.health).to be(true)
    end

    # THE CHECK THAT STOPS THE WRONG MERCHANT BEING BOUND. The credential proves which store it
    # was issued for; this proves that store is the one the connection claims. Without it a
    # credential for store 9 pasted into store 4's connection would bind 9's orders to 4.
    it 'refuses when the store names a different identity than the connection claims' do
      stub_store({ external_store_id: 'storesyria.test:9', name: 'Someone Else' })

      expect { provider.health }.to raise_error(Commerce::Error) { |e| expect(e.code).to eq('AUTH_INVALID') }
    end

    it 'refuses a response with no identity rather than inventing one' do
      stub_store({ name: 'No Id' })

      expect { provider.store_identity }.to raise_error(Commerce::Error) { |e| expect(e.code).to eq('INVALID_RESPONSE') }
    end

    it 'sends the credential and no store identifier of its own' do
      stub_store({ external_store_id: 'storesyria.test:4', name: 'UAT Store' })
      provider.store_identity

      expect(a_request(:get, 'https://storesyria.test/api/lynomia/commerce/v1/store')
        .with(headers: { 'Authorization' => 'Bearer lsc_4_1_deadbeef' })).to have_been_made

      # There is no store id in the path or the query: the credential names the store, so there
      # is nothing here for a caller to tamper with.
      expect(a_request(:get, %r{/store\?.*store}i)).not_to have_been_made
    end
  end

  describe 'order normalization' do
    let(:normalizer) { Commerce::Providers::Storesyria::Normalizer.new(provider, store) }

    def order(overrides = {})
      normalizer.order({
        'id' => '55', 'number' => '020260101120000', 'delivered_status' => 6,
        'payment_status' => 'paid', 'currency' => 'SYP', 'total' => '1500.50',
        'created_at' => '2026-01-01T12:00:00Z', 'items' => [], 'item_count' => 2
      }.merge(overrides))
    end

    it 'maps every delivered_status Store Syria actually writes' do
      {
        0 => 'pending', 1 => 'delivered', 2 => 'cancelled', 3 => 'refunded',
        4 => 'processing', 5 => 'processing', 6 => 'shipped', 7 => 'pending', 8 => 'pending'
      }.each do |raw, canonical|
        expect(order('delivered_status' => raw).status).to eq(canonical), "delivered_status #{raw}"
      end
    end

    # 'Picked Up' is not 'shipped' -- the parcel has not left the store, and a merchant who
    # ships from a warehouse cares about the difference. Both canonicalise to processing, so the
    # raw value has to survive for the agent to see.
    it 'keeps the store raw status even where the canonical value is lossy' do
      expect(order('delivered_status' => 5, 'status_label' => 'Picked Up').provider_status).to eq('Picked Up')
      expect(order('delivered_status' => 4, 'status_label' => 'Confirmed').provider_status).to eq('Confirmed')
    end

    it 'refuses to guess an unknown status' do
      expect(order('delivered_status' => 99).status).to eq('other')
      expect(order('payment_status' => 'weird').payment_status).to eq('unknown')
    end

    # Store Syria stores order money as PHP floats and cart prices as integers. Turning either
    # into a Ruby Float would reintroduce exactly the rounding this vocabulary avoids.
    it 'keeps money as a decimal string' do
      expect(order('total' => '1500.50').total).to eq('1500.5')
      expect(order('total' => 0).total).to eq('0.0')
      expect(order('total' => nil).total).to be_nil
    end

    it 'reports a shipment only where one demonstrably exists' do
      expect(order('delivered_status' => 0).shipments).to be_empty
      expect(order('delivered_status' => 6).shipments.first[:status]).to eq('in_transit')
      expect(order('delivered_status' => 1).shipments.first[:status]).to eq('delivered')
    end

    it 'never invents a tracking number or url' do
      expect(order.tracking).to be_nil
      expect(order('tracking_number' => 'TRK1').tracking).to eq(number: 'TRK1', url: nil)
    end

    it 'falls back to the id when the store never numbered the order' do
      expect(order('number' => nil).order_number).to eq('55')
    end

    it 'turns a malformed order into a safe error rather than leaking the payload' do
      expect { normalizer.order({ 'no' => 'id' }) }
        .to raise_error(Commerce::Error) { |e| expect(e.code).to eq('INVALID_RESPONSE') }
    end
  end

  describe 'carts' do
    let(:normalizer) { Commerce::Providers::Storesyria::Normalizer.new(provider, store) }

    # Store Syria has no durable cart token, so there is no link that restores a basket. A
    # fabricated checkout URL is a bearer credential for someone else's cart, and
    # Commerce::RecoveryUrl would refuse it anyway.
    it 'never produces a recovery url' do
      cart = normalizer.cart('id' => '9', 'total' => '100', 'items' => [])

      expect(cart.recovery_url).to be_nil
      expect(cart.status).to eq('abandoned')
    end
  end

  describe 'admin order url' do
    it 'is built from the validated base url, never from a response' do
      expect(provider.admin_order_url('55')).to eq('https://storesyria.test/order/55')
    end

    it 'refuses a non-numeric order id rather than building a path from it' do
      expect { provider.admin_order_url('../../etc/passwd') }
        .to raise_error(Commerce::Error) { |e| expect(e.code).to eq('INVALID_RESPONSE') }
    end
  end
end
