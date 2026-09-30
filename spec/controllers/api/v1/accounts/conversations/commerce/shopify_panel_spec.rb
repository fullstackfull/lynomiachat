require 'rails_helper'

# The conversation panel with a Shopify store: the same API, matcher and cache as the other providers, nothing
# Shopify-specific.
RSpec.describe 'Conversation commerce API with a Shopify store', type: :request do
  include_context 'with commerce encryption'
  include_context 'with shopify commerce app'

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp.inbox }
  let(:contact) { create(:contact, account: account, name: 'Sara', email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '966551112233') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:store) do
    create(:commerce_store, :shopify, account: account, name: 'Lynomia Demo', external_store_id: '68210001',
                                      base_url: 'https://lynomia-demo.myshopify.com')
  end
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores/#{store.id}" }
  let(:graphql_url) { 'https://lynomia-demo.myshopify.com/admin/api/2026-07/graphql.json' }
  let(:operation) { ->(name) { stub_request(:post, graphql_url).with { |request| JSON.parse(request.body)['query'].include?("query #{name}(") } } }
  let(:orders) { JSON.parse(file_fixture('commerce/shopify/orders.json').read) }

  before do
    account.enable_features!('lynomia_commerce')
    create(:inbox_member, inbox: inbox, user: agent)
    operation.call('LynomiaCustomers').to_return(status: 200, body: file_fixture('commerce/shopify/customers.json').read)
    operation.call('LynomiaOrders').to_return(status: 200, body: orders.to_json)
  end

  it 'links the WhatsApp customer by the verified phone and shows the latest orders with tracking' do
    get path, headers: agent.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body).to include('state' => 'linked', 'store' => { 'id' => store.id, 'name' => 'Lynomia Demo', 'provider' => 'shopify' })
    expect(body['link']).to include('match_source' => 'verified_phone')
    expect(store.customer_links.sole.external_customer_id).to eq('7001')
    expect(body['orders'].pluck('order_number')).to eq(%w[1006 1005 1004 1003 1002])
    expect(body['orders'].first).to include('status' => 'delivered', 'payment_status' => 'paid',
                                            'admin_order_url' => 'https://lynomia-demo.myshopify.com/admin/orders/6001006',
                                            'tracking' => { 'number' => 'ARX100', 'url' => 'https://www.aramex.com/track/ARX100' })
    expect(response.body).not_to include('shopify-access-factory', 'shopify-refresh-factory', shopify_client_secret)
  end

  it 'suggests a guest checkout by the contact email, for an agent to confirm' do
    contact_inbox.update!(source_id: '966500000000')
    contact.update!(email: 'guest.buyer@example.com')
    operation.call('LynomiaCustomers').to_return(status: 200, body: { data: { customers: { nodes: [] } } }.to_json)
    operation.call('LynomiaGuestOrders').to_return(status: 200, body: file_fixture('commerce/shopify/guest_orders.json').read)

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('state' => 'suggested')
    expect(response.parsed_body['candidates'].sole).to include('email' => 'gu***@example.com', 'registered' => false, 'name' => nil)
    expect(store.customer_links).to be_empty
  end

  it 'explains that protected customer data is not approved, and serves nothing cached over it' do
    denied = { errors: [{ message: 'This app is not approved to use the phone field.', extensions: { code: 'ACCESS_DENIED' } }] }
    operation.call('LynomiaCustomers').to_return(status: 200, body: denied.to_json)

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('state' => 'unavailable', 'error' => 'PROTECTED_DATA_NOT_APPROVED')
    expect(store.reload).to be_active
  end

  it 'serves cached orders marked stale while Shopify throttles the store' do
    get path, headers: agent.create_new_auth_token, as: :json
    throttled = { errors: [{ message: 'Throttled', extensions: { code: 'THROTTLED' } }] }
    operation.call('LynomiaOrders').to_return(status: 200, body: throttled.to_json)

    travel(3.minutes) { get path, headers: agent.create_new_auth_token, as: :json }

    expect(response.parsed_body).to include('stale' => true, 'error' => 'RATE_LIMITED')
    expect(response.parsed_body['orders'].size).to eq(5)
  end

  it 'does not hide a revoked token behind cached data: the store needs re-authorization and its cache is dropped' do
    get path, headers: agent.create_new_auth_token, as: :json
    stub_request(:post, graphql_url).to_return(status: 401, body: '{"errors":"[API] Invalid API key or access token"}')
    stub_request(:post, 'https://lynomia-demo.myshopify.com/admin/oauth/access_token').to_return(status: 401, body: '{"error":"invalid_token"}')

    travel(3.minutes) { get path, headers: agent.create_new_auth_token, as: :json }

    expect(response.parsed_body).to include('state' => 'linked', 'orders' => nil, 'error' => 'AUTH_INVALID')
    expect(store.reload).to be_needs_reauth
    expect(store.credentials).to be_nil
  end

  it 'sits next to the other providers of the account and is not offered while Shopify Commerce is off' do
    store
    woo = create(:commerce_store, account: account)
    other_shop = create(:commerce_store, :shopify, account: account)
    index = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores"

    get index, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(store.id, woo.id, other_shop.id)

    InstallationConfig.find_by!(name: 'SHOPIFY_COMMERCE_ENABLED').update!(value: false)
    GlobalConfig.clear_cache
    get index, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('id')).to eq([woo.id])
  end
end
