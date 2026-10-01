require 'rails_helper'

RSpec.describe 'Conversation commerce API', type: :request do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'omar.khalil@example.com', phone_number: nil) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:store) { create(:commerce_store, account: account, name: 'Syria Cosmetics', base_url: 'https://shop.example.com', external_store_id: 'shop.example.com') }
  let(:api) { 'https://shop.example.com/wp-json/wc/v3' }
  let(:orders) { JSON.parse(file_fixture('commerce/woocommerce/orders.json').read).index_by { |order| order['id'] } }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores" }

  before do
    account.enable_features!('lynomia_commerce')
    create(:inbox_member, inbox: inbox, user: agent)
    Commerce::Cache.purge(store)
    allow(Resolv).to receive(:getaddresses).with('shop.example.com').and_return(['93.184.216.34'])
    stub_request(:get, "#{api}/customers").with(query: hash_including('email' => 'omar.khalil@example.com')).to_return(status: 200, body: '[]')
    stub_request(:get, "#{api}/orders").with(query: hash_including('search' => 'omar.khalil@example.com'))
                                       .to_return(status: 200, body: orders.values_at(25, 24, 23).to_json)
  end

  describe 'access' do
    it 'lists the active stores of the account for an agent of the inbox' do
      create(:commerce_store, account: account, status: :disabled)
      create(:commerce_store)

      get path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to eq([{ 'id' => store.id, 'name' => 'Syria Cosmetics', 'provider' => 'woocommerce',
                                                       'linked' => false, 'actions' => false, 'carts' => false }])
    end

    it 'is refused to agents who cannot see the conversation' do
      get "#{path}/#{store.id}", headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'is unavailable when lynomia_commerce is off' do
      account.disable_features!('lynomia_commerce')
      get path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'hides the stores of a provider the installation has switched off, without calling them' do
      salla = create(:commerce_store, :salla, account: account)

      get path, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('provider')).to eq(%w[woocommerce])

      get "#{path}/#{salla.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(a_request(:any, /salla/)).not_to have_been_made
    end

    context 'when the installation offers Salla' do
      include_context 'with salla app'

      it 'lists Salla stores next to WooCommerce ones' do
        salla = create(:commerce_store, :salla, account: account, name: 'Salla Demo')

        get path, headers: agent.create_new_auth_token, as: :json

        expect(response.parsed_body['payload']).to eq([
                                                        { 'id' => store.id, 'name' => 'Syria Cosmetics', 'provider' => 'woocommerce',
                                                          'linked' => false, 'actions' => false, 'carts' => false },
                                                        { 'id' => salla.id, 'name' => 'Salla Demo', 'provider' => 'salla', 'linked' => false,
                                                          'actions' => false, 'carts' => false }
                                                      ])
      end
    end

    it 'never reaches another account\'s store or a disabled store' do
      other = create(:commerce_store)
      disabled = create(:commerce_store, account: account, status: :disabled)

      [other, disabled].each do |target|
        get "#{path}/#{target.id}", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET panel' do
    it 'suggests the customer found by the contact email, masked, with a signed token' do
      get "#{path}/#{store.id}", headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body).to include('state' => 'suggested', 'store' => { 'id' => store.id, 'name' => 'Syria Cosmetics', 'provider' => 'woocommerce' })
      expect(body['candidates'].sole).to include('name' => 'Omar Khalil', 'email' => 'om***@example.com', 'phone' => '+966*******33',
                                                 'registered' => false)
      expect(response.body).not_to include('omar.khalil@', '551112233', 'ck_factory', 'cs_factory')
    end

    it 'says so when the store has no such customer' do
      stub_request(:get, "#{api}/orders").with(query: hash_including('search' => 'omar.khalil@example.com')).to_return(status: 200, body: '[]')

      get "#{path}/#{store.id}", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('state' => 'not_found', 'candidates' => [])
    end

    it 'shows the linked customer\'s latest five orders, normalized' do
      create(:commerce_customer_link, store: store, contact: contact, external_customer_id: '2', match_source: :manual)
      stub_request(:get, "#{api}/orders").with(query: hash_including('customer' => '2'))
                                         .to_return(status: 200, body: orders.values_at(22, 20, 18, 17, 16).to_json)

      get "#{path}/#{store.id}", headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body).to include('state' => 'linked', 'stale' => false)
      expect(body['orders'].pluck('order_number')).to eq(%w[22 20 18 17 16])
      expect(body['orders'].first.keys).to match_array(Commerce::Order.members.map(&:to_s))
      expect(response.body).not_to include('order_key', 'payment_url', '_links', 'customer_ip_address')
    end

    it 'falls back to the last fetched orders, marked stale, when the store times out' do
      create(:commerce_customer_link, store: store, contact: contact, external_customer_id: '2', match_source: :manual)
      stub_request(:get, "#{api}/orders").with(query: hash_including('customer' => '2'))
                                         .to_return(status: 200, body: orders.values_at(22).to_json).then.to_timeout
      get "#{path}/#{store.id}", headers: agent.create_new_auth_token, as: :json
      fetched_at = response.parsed_body['fetched_at']

      travel(18.minutes) { get "#{path}/#{store.id}", headers: agent.create_new_auth_token, as: :json }

      expect(response.parsed_body).to include('state' => 'linked', 'stale' => true, 'error' => 'TIMEOUT', 'fetched_at' => fetched_at)
      expect(response.parsed_body['orders'].pluck('order_number')).to eq(['22'])
    end

    it 'reports the store as unavailable when there is nothing cached' do
      create(:commerce_customer_link, store: store, contact: contact, external_customer_id: '2', match_source: :manual)
      stub_request(:get, "#{api}/orders").with(query: hash_including('customer' => '2')).to_return(status: 503)

      get "#{path}/#{store.id}", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('state' => 'linked', 'orders' => nil, 'error' => 'STORE_UNAVAILABLE')
    end

    it 'flags the store for an administrator when its keys stop working' do
      stub_request(:get, "#{api}/customers").with(query: hash_including('email' => 'omar.khalil@example.com')).to_return(status: 401)

      get "#{path}/#{store.id}", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('state' => 'unavailable', 'error' => 'AUTH_INVALID')
      expect(store.reload).to be_needs_reauth
    end
  end

  describe 'search and link' do
    it 'links a candidate from a search, then changes and removes the link, auditing each step' do
      get "#{path}/#{store.id}/customers", headers: agent.create_new_auth_token, params: { query: 'Omar.Khalil@example.com' }
      token = response.parsed_body['candidates'].sole['token']

      post "#{path}/#{store.id}/link", headers: agent.create_new_auth_token, as: :json, params: { token: token }

      expect(response.parsed_body).to include('state' => 'linked')
      expect(store.customer_links.sole).to have_attributes(contact: contact, external_customer_id: 'guest:omar.khalil@example.com',
                                                           match_source: 'manual', confirmed_by: agent)

      delete "#{path}/#{store.id}/link", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(store.customer_links.sole).to have_attributes(match_source: 'suppressed', confirmed_by: agent)

      if defined?(Enterprise::AuditLog)
        expect(Enterprise::AuditLog.where(auditable_type: 'Commerce::CustomerLink').order(:id).pluck(:comment, :audited_changes))
          .to eq([['commerce.customer_link_created', { 'match_source' => 'manual' }],
                  ['commerce.customer_link_removed', { 'match_source' => %w[manual suppressed] }]])
      end
    end

    it 'audits a changed link with the previous match source' do
      create(:commerce_customer_link, store: store, contact: contact, external_customer_id: '2', match_source: :verified_phone)
      get "#{path}/#{store.id}/customers", headers: agent.create_new_auth_token, params: { query: 'omar.khalil@example.com' }

      post "#{path}/#{store.id}/link", headers: agent.create_new_auth_token, as: :json,
                                       params: { token: response.parsed_body['candidates'].sole['token'] }

      expect(store.customer_links.sole).to have_attributes(external_customer_id: 'guest:omar.khalil@example.com', match_source: 'manual')
      if defined?(Enterprise::AuditLog)
        expect(Enterprise::AuditLog.where(auditable_type: 'Commerce::CustomerLink').last)
          .to have_attributes(comment: 'commerce.customer_link_changed', audited_changes: { 'match_source' => %w[verified_phone manual] })
      end
    end

    it 'refuses a forged or foreign token' do
      payload = { 'store_id' => store.id, 'contact_id' => contact.id, 'external_customer_id' => '2' }
      forged = ActiveSupport::MessageEncryptor.new(SecureRandom.bytes(32)).encrypt_and_sign(payload, purpose: :commerce_customer_link)
      foreign = ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key('commerce_customer_link', 32))
                                               .encrypt_and_sign(payload.merge('contact_id' => create(:contact, account: account).id),
                                                                 purpose: :commerce_customer_link)

      [forged, foreign, 'garbage'].each do |token|
        post "#{path}/#{store.id}/link", headers: agent.create_new_auth_token, as: :json, params: { token: token }
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(Commerce::CustomerLink.count).to eq(0)
    end

    it 'refuses an expired token' do
      get "#{path}/#{store.id}/customers", headers: agent.create_new_auth_token, params: { query: 'omar.khalil@example.com' }
      token = response.parsed_body['candidates'].sole['token']

      travel(16.minutes) { post "#{path}/#{store.id}/link", headers: agent.create_new_auth_token, as: :json, params: { token: token } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'does not search by name or by a local number without country code' do
      ['Omar Khalil', '0551112233', ''].each do |query|
        get "#{path}/#{store.id}/customers", headers: agent.create_new_auth_token, params: { query: query }
        expect(response.parsed_body).to eq('error' => { 'code' => 'INVALID_QUERY' })
      end
    end
  end

  describe 'multi-store and multi-tenant' do
    let(:second_store) { create(:commerce_store, account: account, name: 'Second', base_url: 'https://second.example.com', external_store_id: 'second.example.com') }
    let(:account_b) { create(:account) }
    let(:store_b) { create(:commerce_store, account: account_b, base_url: 'https://b.example.com', external_store_id: 'b.example.com') }

    it 'keeps links per store: linking in A1 does not link A2, and B1 is unreachable' do
      create(:commerce_customer_link, store: store, contact: contact, external_customer_id: '2')
      second_store

      get path, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].map { |s| [s['id'], s['linked']] }).to eq([[store.id, true], [second_store.id, false]])

      get "#{path}/#{store_b.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'cannot link a contact to a store of another account' do
      account_b.enable_features!('lynomia_commerce')
      admin_b = create(:user, account: account_b, role: :administrator)

      post "/api/v1/accounts/#{account_b.id}/conversations/#{conversation.display_id}/commerce/stores/#{store_b.id}/link",
           headers: admin_b.create_new_auth_token, as: :json, params: { token: 'x' }

      expect(response).to have_http_status(:not_found)
      expect(Commerce::CustomerLink.count).to eq(0)
    end
  end
end
