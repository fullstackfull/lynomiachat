require 'rails_helper'

RSpec.describe 'Commerce stores API', type: :request do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:api) { 'https://shop.example.com/wp-json/wc/v3' }
  let(:keys) { { consumer_key: "ck_#{'a' * 40}", consumer_secret: "cs_#{'b' * 40}" } }
  let(:stores_path) { "/api/v1/accounts/#{account.id}/commerce/stores" }

  before do
    account.enable_features!('lynomia_commerce')
    allow(Resolv).to receive(:getaddresses).with('shop.example.com').and_return(['93.184.216.34'])
    stub_request(:get, "#{api}?_fields=namespace").to_return(status: 200, body: '{"namespace":"wc/v3"}')
    stub_request(:get, %r{\A#{api}/(orders|customers)\?}).to_return(status: 200, body: '[]')
  end

  describe 'POST /commerce/stores' do
    it 'connects a WooCommerce store and never returns the keys' do
      post stores_path, headers: admin.create_new_auth_token, as: :json,
                        params: keys.merge(provider: 'woocommerce', base_url: 'https://shop.example.com', name: 'Syria Cosmetics')

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('provider' => 'woocommerce', 'name' => 'Syria Cosmetics', 'status' => 'active',
                                              'base_url' => 'https://shop.example.com')
      expect(response.body).not_to include('ck_', 'cs_', 'credentials')
      expect(account.commerce_stores.sole.credentials).to eq(keys.stringify_keys)
    end

    it 'is for administrators only' do
      post stores_path, headers: agent.create_new_auth_token, as: :json,
                        params: keys.merge(provider: 'woocommerce', base_url: 'https://shop.example.com')

      expect(response).to have_http_status(:unauthorized)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'is unavailable when lynomia_commerce is off' do
      account.disable_features!('lynomia_commerce')
      post stores_path, headers: admin.create_new_auth_token, as: :json,
                        params: keys.merge(provider: 'woocommerce', base_url: 'https://shop.example.com')

      expect(response).to have_http_status(:unauthorized)
      expect(Commerce::Store.count).to eq(0)
    end

    it 'returns a safe error code when the store rejects the keys' do
      stub_request(:get, "#{api}?_fields=namespace")
        .to_return(status: 401, body: '{"code":"woocommerce_rest_authentication_error","message":"Consumer secret is invalid."}')

      post stores_path, headers: admin.create_new_auth_token, as: :json,
                        params: keys.merge(provider: 'woocommerce', base_url: 'https://shop.example.com')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => { 'code' => 'AUTH_INVALID' })
      expect(Commerce::Store.count).to eq(0)
    end

    it 'rejects internal store URLs' do
      post stores_path, headers: admin.create_new_auth_token, as: :json,
                        params: keys.merge(provider: 'woocommerce', base_url: 'http://localhost:8081')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('code' => 'INVALID_STORE_URL')
    end

    [{ consumer_key: 'ck_short' }, { consumer_secret: "cs_#{'b' * 40}\r\nX-Evil: 1" }, { provider: 'shopify' }, { base_url: nil }].each do |bad|
      it "rejects malformed input #{bad.keys.first}" do
        post stores_path, headers: admin.create_new_auth_token, as: :json,
                          params: keys.merge(provider: 'woocommerce', base_url: 'https://shop.example.com').merge(bad)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(a_request(:any, /.*/)).not_to have_been_made
      end
    end
  end

  describe 'existing stores' do
    let!(:store) { create(:commerce_store, account: account, base_url: 'https://shop.example.com', external_store_id: 'shop.example.com') }
    let(:other_account) { create(:account) }
    let!(:other_store) { create(:commerce_store, account: other_account) }

    it 'lists only this account\'s stores, without credentials' do
      get stores_path, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('id')).to eq([store.id])
      expect(response.body).not_to include('ck_factory', 'cs_factory')
    end

    it 'renames, disables and re-enables a store' do
      patch "#{stores_path}/#{store.id}", headers: admin.create_new_auth_token, as: :json, params: { name: 'Main store', status: 'disabled' }
      expect(response.parsed_body).to include('name' => 'Main store', 'status' => 'disabled')

      patch "#{stores_path}/#{store.id}", headers: admin.create_new_auth_token, as: :json, params: { status: 'active' }
      expect(response.parsed_body).to include('status' => 'active')
    end

    it 'rotates credentials through the health check' do
      rotated = { consumer_key: "ck_#{'c' * 40}", consumer_secret: "cs_#{'d' * 40}" }
      patch "#{stores_path}/#{store.id}", headers: admin.create_new_auth_token, as: :json, params: rotated

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('ck_', 'cs_')
      expect(store.reload.credentials).to eq(rotated.stringify_keys)
    end

    it 'disconnects a store' do
      delete "#{stores_path}/#{store.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(store.reload).to have_attributes(status: 'disconnected', credentials: nil)
    end

    it 'cannot touch another account\'s store' do
      other_account.enable_features!('lynomia_commerce')
      other_admin = create(:user, account: other_account, role: :administrator)

      patch "/api/v1/accounts/#{other_account.id}/commerce/stores/#{store.id}", headers: other_admin.create_new_auth_token, as: :json,
                                                                                params: { status: 'disabled' }
      expect(response).to have_http_status(:not_found)

      delete "#{stores_path}/#{other_store.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(other_store.reload).to be_active
    end
  end
end
