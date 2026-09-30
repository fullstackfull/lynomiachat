require 'rails_helper'

RSpec.describe Commerce::Store do
  include_context 'with commerce encryption'

  let(:credentials) { { 'consumer_key' => 'ck_live_4f1c2b', 'consumer_secret' => 'cs_live_9a8b7c' } }

  describe 'credentials' do
    it 'encrypts them at rest' do
      store = create(:commerce_store, credentials: credentials)

      raw = described_class.connection.select_value("SELECT credentials FROM commerce_stores WHERE id = #{store.id}")
      expect(raw).not_to include('ck_live_4f1c2b')
      expect(raw).not_to include('cs_live_9a8b7c')
      expect(store.reload.credentials).to eq(credentials)
      expect(store.encrypted_attribute?(:credentials)).to be(true)
    end

    it 'keeps them out of JSON and inspect output' do
      store = create(:commerce_store, credentials: credentials)

      expect(store.as_json).not_to have_key('credentials')
      expect(store.to_json).not_to include('cs_live_9a8b7c')
      expect(store.inspect).not_to include('cs_live_9a8b7c')
    end

    it 'refuses to save them when Active Record encryption is not configured' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
      store = build(:commerce_store, credentials: credentials)

      expect(store).not_to be_valid
      expect(store.errors.details[:credentials]).to include(error: :encryption_not_configured)
      expect { store.save }.not_to change(described_class, :count)
    end
  end

  describe 'ownership' do
    it 'lets a store belong to one account only' do
      create(:commerce_store, external_store_id: 'shop.example.com')
      other_account_store = build(:commerce_store, external_store_id: 'shop.example.com', account: create(:account))

      expect(other_account_store).not_to be_valid
      expect(other_account_store.errors.details[:external_store_id]).to include(a_hash_including(error: :taken))
      expect { other_account_store.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows several stores in one account' do
      account = create(:account)
      create_list(:commerce_store, 2, account: account)

      expect(account.commerce_stores.count).to eq(2)
    end

    it 'is removed with its account' do
      store = create(:commerce_store)
      create(:commerce_customer_link, store: store)

      store.account.destroy!

      expect(described_class.exists?(store.id)).to be(false)
      expect(Commerce::CustomerLink.where(commerce_store_id: store.id)).to be_empty
    end
  end

  describe 'status' do
    it 'defaults to active and supports the lifecycle states' do
      expect(create(:commerce_store)).to be_active
      expect(described_class.statuses.keys).to eq(%w[active disabled needs_reauth disconnected])
    end
  end

  describe 'feature flag' do
    it 'is a plan-assignable account feature, off by default' do
      flag = YAML.safe_load(Rails.root.join('config/features.yml').read).find { |feature| feature['name'] == 'lynomia_commerce' }

      expect(flag).to include('enabled' => false, 'column' => 'feature_flags_ext_1')
      expect(BillingPlan.assignable_features.pluck('name')).to include('lynomia_commerce')
    end
  end
end
