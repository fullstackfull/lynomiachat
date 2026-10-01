require 'rails_helper'

# Lynomia Commerce production gate (docs/commerce/23-real-uat-and-production-gate.md): one account with a WooCommerce, a
# Salla, a Zid and a Shopify store, and one WhatsApp contact known to all four. Each provider answers from its own
# documented-shape fixtures; everything on Lynomia's side runs for real: conversation API, matcher, cache, providers,
# token managers, webhooks, ownership rules. A gate walks the whole account, hence the helper and expectation counts.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Commerce production gate: one account, four providers', type: :request do
  include_context 'with four commerce stores'

  it 'lists the four stores with their providers, and each store links its own customer and shows only its own orders' do
    get stores_path, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].map { |store| store.values_at('name', 'provider') })
      .to eq([['Woo Store', 'woocommerce'], ['Salla Store', 'salla'], ['Zid Store', 'zid'], ['Shopify Store', 'shopify']])

    expected = {
      woo => %w[25 24 23], salla => %w[30013 30012 30011 30015 30014], zid => %w[41000102 41000101 41000103],
      shopify => %w[1006 1005 1004 1003 1002]
    }
    bodies = expected.to_h do |store, numbers|
      body = panel.call(store)
      expect(body).to include('state' => 'linked', 'store' => { 'id' => store.id, 'name' => store.name, 'provider' => store.provider })
      expect(body['link']).to include('match_source' => 'verified_phone')
      expect(body['orders'].pluck('order_number')).to eq(numbers)
      expect(body['orders'].pluck('provider').uniq).to eq([store.provider])
      [store, body]
    end

    links = Commerce::CustomerLink.where(contact: contact).to_h { |link| [link.store.provider, link.external_customer_id] }
    expect(links).to eq('woocommerce' => 'guest:+966551112233', 'salla' => '1227534533', 'zid' => '90001', 'shopify' => '7001')
    expect(expected.values.flatten.uniq.size).to eq(expected.values.flatten.size)

    # Tracking: https only, the provider's own shipment, several shipments kept; WooCommerce has none.
    trackings = bodies.transform_values { |body| body['orders'].filter_map { |order| order['tracking'] } }
    expect(trackings[woo]).to eq([])
    expect(trackings.values.flatten.pluck('url').compact).to all(start_with('https://'))
    expect(trackings[salla]).to include('number' => 'AX123456789SA', 'url' => 'https://www.aramex.com/track/results?ShipmentNumber=AX123456789SA')
    expect(trackings[zid]).to include('number' => 'KWB123456789SA', 'url' => 'https://track.kwickbox.example/KWB123456789SA')
    delivered = bodies[shopify]['orders'].find { |order| order['order_number'] == '1006' }
    expect(delivered['shipments'].pluck('tracking_number')).to eq(%w[ARX100 SMSA200])
    expect(bodies[shopify]['orders'].flat_map { |order| order['shipments'] }.pluck('tracking_url').compact).to all(start_with('https://'))
    expect(response.body).not_to include('salla-access-factory', 'zid-manager-factory', 'zid-authorization-factory', 'shopify-access-factory',
                                         'cs_factory', 'ck_factory')
  end

  it 'keeps each store in its own cache: an order event drops and refreshes only that store customer orders' do
    [woo, salla, zid, shopify].each { |store| panel.call(store) }
    before_keys = [woo, salla, zid, shopify].index_with { |store| cache_keys.call(store) }
    expect(before_keys.values).to all(be_present)
    expect(before_keys.values.flatten.uniq.size).to eq(before_keys.values.flatten.size)

    zid.update!(credentials: zid.credentials.merge('webhook_username' => 'u' * 32, 'webhook_password' => 'p' * 64))
    body = { id: 6_001_006, customer: { id: 7001 } }.to_json
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', shopify_client_secret, body))
    perform_enqueued_jobs(only: Commerce::Shopify::WebhookJob) do
      post '/webhooks/shopify_commerce', params: body,
                                         headers: { 'Content-Type' => 'application/json', 'X-Shopify-Topic' => 'orders/updated',
                                                    'X-Shopify-Shop-Domain' => 'lynomia-demo.myshopify.com', 'X-Shopify-Webhook-Id' => 'gate-1',
                                                    'X-Shopify-Hmac-Sha256' => signature }
    end

    expect(cache_keys.call(shopify).size).to eq(before_keys[shopify].size - 1)
    [woo, salla, zid].each { |store| expect(cache_keys.call(store)).to match_array(before_keys[store]) }

    perform_enqueued_jobs(only: Commerce::RefreshJob)
    expect(cache_keys.call(shopify)).to match_array(before_keys[shopify])
    [woo, salla, zid].each { |store| expect(cache_keys.call(store)).to match_array(before_keys[store]) }
  end

  it 'serves data fresh for 120 seconds, stale for at most a day on an outage, and never over rejected credentials' do
    woo_list = a_request(:get, "#{woo_api}/orders").with(query: hash_including('customer' => '0', 'search' => '551112233'))
    panel.call(woo)
    travel(119.seconds) { panel.call(woo) }
    expect(woo_list).to have_been_made.once
    travel(121.seconds) do
      panel.call(woo)
      expect(cache_keys.call(woo).map { |key| Redis::Alfred.ttl(key) }).to all(be_between(1, 24.hours.to_i))
    end
    expect(woo_list).to have_been_made.twice

    woo_search.to_return(status: 503)
    body = travel(23.hours) { panel.call(woo) }
    expect(body).to include('stale' => true, 'error' => 'STORE_UNAVAILABLE')
    expect(body['orders'].pluck('order_number')).to eq(%w[25 24 23])

    [salla, zid, shopify].each { |store| panel.call(store) }
    woo_search.to_return(status: 401)
    salla_customer_orders.to_return(status: 401, body: '{"status":401,"success":false}')
    zid_customer_orders.to_return(status: 401, body: '{"status":401,"success":false}')
    stub_request(:post, 'https://oauth.zid.sa/oauth/token').to_return(status: 400, body: '{"error":"invalid_grant"}')
    stub_request(:post, shopify_graphql).to_return(status: 401, body: '{"errors":"[API] Invalid API key or access token"}')
    stub_request(:post, 'https://lynomia-demo.myshopify.com/admin/oauth/access_token').to_return(status: 400, body: '{"error":"invalid_request"}')

    travel(24.hours) do
      [woo, salla, zid, shopify].each do |store|
        body = panel.call(store)
        expect(body).to include('orders' => nil, 'error' => 'AUTH_INVALID'), store.provider
        expect(store.reload).to be_needs_reauth
        expect(cache_keys.call(store)).to be_empty
      end
    end
  end

  it 'never links a customer automatically without one exact verified match' do
    omar = JSON.parse(file_fixture('commerce/salla/customers.json').read)['data'].first
    stub_request(:get, "#{salla_api}/customers").with(query: hash_including('keyword' => '551112233'))
                                                .to_return(salla_envelope.call([omar, omar.merge('id' => 1_227_534_600)]))
    expect(panel.call(salla)).to include('state' => 'multiple')

    web = create(:contact, account: account, email: 'Omar.Khalil@Example.com', phone_number: nil)
    web_conversation = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: web)
    create(:inbox_member, inbox: web_conversation.inbox, user: agent)
    stub_request(:get, "#{woo_api}/customers").with(query: hash_including('email' => 'omar.khalil@example.com')).to_return(status: 200, body: '[]')
    stub_request(:get, "#{woo_api}/orders").with(query: hash_including('search' => 'omar.khalil@example.com'))
                                           .to_return(status: 200, body: woo_orders.values_at(25, 24, 23).to_json)
    stub_request(:get, "#{salla_api}/customers").with(query: hash_including('keyword' => 'omar.khalil@example.com'))
                                                .to_return(status: 200, body: file_fixture('commerce/salla/customers.json').read)
    stub_request(:get, zid_orders).with(query: hash_including('search_term' => 'omar.khalil@example.com'))
                                  .to_return(status: 200, body: zid_fixture.to_json)
    shopify_operation.call('LynomiaGuestOrders').to_return(status: 200, body: { data: { orders: { nodes: [] } } }.to_json)

    states = [woo, salla, zid, shopify].to_h do |store|
      get "/api/v1/accounts/#{account.id}/conversations/#{web_conversation.display_id}/commerce/stores/#{store.id}",
          headers: agent.create_new_auth_token, as: :json
      [store.provider, response.parsed_body['state']]
    end

    expect(states).to eq('woocommerce' => 'suggested', 'salla' => 'suggested', 'zid' => 'not_found', 'shopify' => 'not_found')
    expect(Commerce::CustomerLink.where(contact: [contact, web])).to be_empty
  end

  describe 'another account' do
    let(:other) { create(:account) }
    let(:other_admin) { create(:user, account: other, role: :administrator) }
    let(:other_conversation) { create(:conversation, account: other, inbox: create(:inbox, account: other)) }

    before { other.enable_features!('lynomia_commerce') }

    it 'cannot read, change or disconnect these stores' do
      get "/api/v1/accounts/#{other.id}/conversations/#{other_conversation.display_id}/commerce/stores/#{zid.id}",
          headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      get "#{stores_path}/#{zid.id}", headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      patch "/api/v1/accounts/#{other.id}/commerce/stores/#{shopify.id}", params: { status: 'disabled' },
                                                                          headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      delete "/api/v1/accounts/#{other.id}/commerce/stores/#{salla.id}", headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      expect([woo, salla, zid, shopify].map { |store| store.reload.status }).to all(eq('active'))
      expect(a_request(:any, /salla|zid|myshopify|shop\.example/)).not_to have_been_made
    end

    it 'cannot claim any of these stores' do
      connection = Commerce::StoreConnection.new(account: other, user: other_admin)
      [woo, salla, zid, shopify].each do |store|
        claim = other.commerce_stores.new(provider: store.provider, base_url: store.base_url, created_by: other_admin)

        expect { connection.attach(claim, { external_store_id: store.external_store_id, name: 'Claimed' }, { 'access_token' => 'x' }) }
          .to raise_error(Commerce::Error, 'STORE_ALREADY_CONNECTED')
        expect(store.reload).to have_attributes(account_id: account.id, name: store.name, status: 'active')
      end
    end

    it "cannot reuse another store's webhook credentials or another account's OAuth state" do
      zid.update!(credentials: zid.credentials.merge('webhook_username' => 'u' * 32, 'webhook_password' => 'p' * 64))
      other_zid = create(:commerce_store, :zid, account: other, external_store_id: '318002')
      other_zid.update!(credentials: other_zid.credentials.merge('webhook_username' => 'v' * 32, 'webhook_password' => 'q' * 64))
      auth = ActionController::HttpAuthentication::Basic.encode_credentials('u' * 32, 'p' * 64)

      post "/webhooks/zid/#{other_zid.external_store_id}", params: '{}', headers: { 'Authorization' => auth, 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)

      issued = Commerce::OauthState.issue('shopify', account: account, user: admin, shop: 'lynomia-demo.myshopify.com')
      expect(Commerce::OauthState.consume('shopify', issued.state, SecureRandom.urlsafe_base64(32))).to be_nil
      expect(Commerce::OauthState.consume('zid', issued.state, issued.nonce)).to be_nil
      expect(Commerce::OauthState.consume('shopify', issued.state, issued.nonce)).to include('account_id' => account.id)
      expect(Commerce::OauthState.consume('shopify', issued.state, issued.nonce)).to be_nil
    end
  end

  describe 'emergency switches' do
    it 'switching one provider off stops only that provider, and the conversation itself is unaffected' do
      InstallationConfig.find_by!(name: 'ZID_ENABLED').update!(value: false)
      GlobalConfig.clear_cache

      get stores_path, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('provider')).to eq(%w[woocommerce salla shopify])
      get "#{stores_path}/#{zid.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(panel.call(shopify)).to include('state' => 'linked')
      expect(a_request(:get, /api\.zid\.sa/)).not_to have_been_made

      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(zid.reload).to be_active
    end

    it 'switching Commerce off for the account hides every store and leaves conversations working' do
      account.disable_features!('lynomia_commerce')

      get stores_path, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(a_request(:any, /salla|zid|myshopify|shop\.example/)).not_to have_been_made
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
