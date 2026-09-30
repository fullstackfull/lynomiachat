require 'rails_helper'

# The conversation panel with a Zid store: the same API, matcher and cache as WooCommerce and Salla, nothing Zid-specific.
RSpec.describe 'Conversation commerce API with a Zid store', type: :request do
  include_context 'with commerce encryption'
  include_context 'with zid app'
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp.inbox }
  let(:contact) { create(:contact, account: account, name: 'Sara', email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '966551112233') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:store) do
    create(:commerce_store, :zid, account: account, name: 'متجر الياسمين', external_store_id: '318001', metadata: { 'time_zone' => 'Asia/Riyadh' })
  end
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores/#{store.id}" }
  let(:orders_url) { 'https://api.zid.sa/v1/managers/store/orders' }
  let(:orders) { JSON.parse(file_fixture('commerce/zid/orders.json').read) }
  let(:customer_orders) { stub_request(:get, orders_url).with(query: hash_including('customer_id' => '90001')) }

  def respond(list)
    { status: 200, body: orders.merge('orders' => list).to_json }
  end

  before do
    account.enable_features!('lynomia_commerce')
    create(:inbox_member, inbox: inbox, user: agent)
    stub_request(:get, orders_url).with(query: hash_including('search_term' => '551112233')).to_return(respond(orders['orders']))
    customer_orders.to_return(respond(orders['orders']))
  end

  it 'links the WhatsApp customer by the verified phone and shows the latest orders with tracking' do
    get path, headers: agent.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body).to include('state' => 'linked', 'store' => { 'id' => store.id, 'name' => 'متجر الياسمين', 'provider' => 'zid' })
    expect(body['link']).to include('match_source' => 'verified_phone')
    expect(store.customer_links.sole.external_customer_id).to eq('90001')
    expect(body['orders'].pluck('order_number')).to eq(%w[41000102 41000101 41000103])
    expect(body['orders'].first).to include('status' => 'shipped', 'payment_status' => 'paid',
                                            'tracking' => { 'number' => 'KWB123456789SA', 'url' => 'https://track.kwickbox.example/KWB123456789SA' })
    expect(response.body).not_to include('zid-authorization-factory', 'zid-manager-factory', 'zid-refresh-factory', 'ZdA1b2C3d4')
  end

  it 'never links a marketplace customer, whose details Zid masks' do
    marketplace = orders['orders'].select { |raw| raw['is_marketplace_order'] }
    stub_request(:get, orders_url).with(query: hash_including('search_term' => '551112233')).to_return(respond(marketplace))

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('state' => 'not_found', 'candidates' => [])
    expect(store.customer_links).to be_empty
  end

  it "reads a customer's orders again right after Zid reports an order event for them" do
    store.update!(credentials: store.credentials.merge('webhook_username' => 'u' * 32, 'webhook_password' => 'p' * 64))
    get path, headers: agent.create_new_auth_token, as: :json
    changed = orders['orders'].first.merge('order_status' => { 'name' => 'Delivered', 'code' => 'delivered' })
    customer_orders.to_return(respond([changed]))
    auth = ActionController::HttpAuthentication::Basic.encode_credentials('u' * 32, 'p' * 64)

    perform_enqueued_jobs do
      post "/webhooks/zid/#{store.external_store_id}", params: changed.to_json,
                                                       headers: { 'Authorization' => auth, 'Content-Type' => 'application/json' }
    end
    get path, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['orders'].pluck('status')).to eq(['delivered'])
  end

  it 'serves cached orders marked stale while Zid is rate limiting the store' do
    get path, headers: agent.create_new_auth_token, as: :json
    customer_orders.to_return(status: 429, headers: { 'Retry-After' => '30' })

    travel(3.minutes) { get path, headers: agent.create_new_auth_token, as: :json }

    expect(response.parsed_body).to include('stale' => true, 'error' => 'RATE_LIMITED')
    expect(response.parsed_body['orders'].size).to eq(3)
  end

  it 'does not hide a revoked authorization behind cached data: the store needs re-authorization and its cache is dropped' do
    get path, headers: agent.create_new_auth_token, as: :json
    customer_orders.to_return(status: 401, body: '{"status":401,"success":false}')
    stub_request(:post, 'https://oauth.zid.sa/oauth/token').to_return(status: 400, body: '{"error":"invalid_grant"}')

    travel(3.minutes) { get path, headers: agent.create_new_auth_token, as: :json }

    expect(response.parsed_body).to include('state' => 'linked', 'orders' => nil, 'error' => 'AUTH_INVALID')
    expect(store.reload).to be_needs_reauth
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to eq([])
  end
end
