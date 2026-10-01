# One account with a WooCommerce, a Salla, a Zid and a Shopify store, and one WhatsApp contact known to all four
# (docs/commerce/23 §6, docs/commerce/25-customer-360.md). Each provider answers from its own documented-shape fixtures;
# the contact's phone links it automatically in every store. Used by the production gate and Customer 360 specs.
# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.shared_context 'with four commerce stores' do
  include_context 'with commerce encryption'
  include_context 'with salla app'
  include_context 'with zid app'
  include_context 'with shopify commerce app'
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:contact) { create(:contact, account: account, name: 'Omar', email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: whatsapp.inbox, source_id: '966551112233') }
  let(:conversation) { create(:conversation, account: account, inbox: whatsapp.inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:stores_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores" }

  let!(:woo) { create(:commerce_store, account: account, name: 'Woo Store', base_url: 'https://shop.example.com', external_store_id: 'shop.example.com') }
  let!(:salla) { create(:commerce_store, :salla, account: account, name: 'Salla Store', external_store_id: '1234509876') }
  let!(:zid) do
    create(:commerce_store, :zid, account: account, name: 'Zid Store', external_store_id: '318001', metadata: { 'time_zone' => 'Asia/Riyadh' })
  end
  let!(:shopify) do
    create(:commerce_store, :shopify, account: account, name: 'Shopify Store', external_store_id: '68210001', base_url: 'https://lynomia-demo.myshopify.com')
  end

  let(:woo_api) { 'https://shop.example.com/wp-json/wc/v3' }
  let(:salla_api) { 'https://api.salla.dev/admin/v2' }
  let(:zid_orders) { 'https://api.zid.sa/v1/managers/store/orders' }
  let(:shopify_graphql) { 'https://lynomia-demo.myshopify.com/admin/api/2026-07/graphql.json' }
  let(:woo_orders) { JSON.parse(file_fixture('commerce/woocommerce/orders.json').read).index_by { |order| order['id'] } }
  let(:salla_orders) { JSON.parse(file_fixture('commerce/salla/orders.json').read)['data'] }
  let(:zid_fixture) { JSON.parse(file_fixture('commerce/zid/orders.json').read) }
  let(:shopify_operation) do
    ->(name) { stub_request(:post, shopify_graphql).with { |request| JSON.parse(request.body)['query'].include?("query #{name}(") } }
  end
  let(:salla_envelope) { ->(data) { { status: 200, body: { status: 200, success: true, data: data }.to_json } } }
  let(:woo_search) { stub_request(:get, "#{woo_api}/orders").with(query: hash_including('search' => '551112233')) }
  let(:salla_customer_orders) { stub_request(:get, "#{salla_api}/orders").with(query: hash_including('customer_id' => '1227534533')) }
  let(:zid_customer_orders) { stub_request(:get, zid_orders).with(query: hash_including('customer_id' => '90001')) }
  let(:panel) do
    lambda do |store, user = agent|
      get "#{stores_path}/#{store.id}", headers: user.create_new_auth_token, as: :json
      response.parsed_body
    end
  end
  let(:cache_keys) do
    lambda do |store|
      keys = []
      Redis::Alfred.scan_each(match: "COMMERCE::V1::ACCOUNT::#{account.id}::STORE::#{store.id}::*") { |key| keys << key }
      keys
    end
  end

  before do
    account.enable_features!('lynomia_commerce')
    create(:inbox_member, inbox: whatsapp.inbox, user: agent)
    [woo, salla, zid, shopify].each { |store| Commerce::Cache.purge(store) }
    # Every provider host resolves to a public address for the SSRF check (the shared contexts each stub their own).
    { 'shop.example.com' => '93.184.216.34', 'accounts.salla.sa' => '93.184.216.40', 'api.salla.dev' => '93.184.216.41',
      'oauth.zid.sa' => '93.184.216.50', 'api.zid.sa' => '93.184.216.51', 'lynomia-demo.myshopify.com' => '93.184.216.60' }.each do |host, ip|
      allow(Resolv).to receive(:getaddresses).with(host).and_return([ip])
    end

    woo_search.to_return(status: 200, body: woo_orders.values_at(25, 24, 23).to_json)
    stub_request(:get, "#{salla_api}/customers").with(query: hash_including('keyword' => '551112233'))
                                                .to_return(status: 200, body: file_fixture('commerce/salla/customers.json').read)
    salla_customer_orders.to_return(salla_envelope.call(salla_orders))
    stub_request(:get, "#{salla_api}/shipments").with(query: hash_including({})).to_return(salla_envelope.call([]))
    stub_request(:get, "#{salla_api}/shipments").with(query: { 'order_id' => '1861092002' })
                                                .to_return(status: 200, body: file_fixture('commerce/salla/shipments.json').read)
    stub_request(:get, zid_orders).with(query: hash_including('search_term' => '551112233')).to_return(status: 200, body: zid_fixture.to_json)
    zid_customer_orders.to_return(status: 200, body: zid_fixture.to_json)
    shopify_operation.call('LynomiaCustomers').to_return(status: 200, body: file_fixture('commerce/shopify/customers.json').read)
    shopify_operation.call('LynomiaOrders').to_return(status: 200, body: file_fixture('commerce/shopify/orders.json').read)
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
