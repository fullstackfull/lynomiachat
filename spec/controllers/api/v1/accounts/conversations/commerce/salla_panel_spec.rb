require 'rails_helper'

# The conversation panel with a Salla store: the same API, matcher and cache as WooCommerce, nothing Salla-specific.
RSpec.describe 'Conversation commerce API with a Salla store', type: :request do
  include_context 'with commerce encryption'
  include_context 'with salla app'

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp.inbox }
  let(:contact) { create(:contact, account: account, name: 'Omar', email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '966551112233') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:store) { create(:commerce_store, :salla, account: account, name: 'Salla Demo', external_store_id: '1234509876') }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores/#{store.id}" }
  let(:api) { 'https://api.salla.dev/admin/v2' }
  let(:orders) { JSON.parse(file_fixture('commerce/salla/orders.json').read) }

  def respond(data)
    { status: 200, body: { status: 200, success: true, data: data }.to_json }
  end

  def orders_stub
    stub_request(:get, "#{api}/orders").with(query: hash_including('customer_id' => '1227534533'))
  end

  before do
    account.enable_features!('lynomia_commerce')
    create(:inbox_member, inbox: inbox, user: agent)
    stub_request(:get, "#{api}/customers").with(query: hash_including('keyword' => '551112233'))
                                          .to_return(status: 200, body: file_fixture('commerce/salla/customers.json').read)
    orders_stub.to_return(respond(orders['data']))
    stub_request(:get, "#{api}/shipments").with(query: hash_including({})).to_return(respond([]))
    stub_request(:get, "#{api}/shipments").with(query: { 'order_id' => '1861092002' })
                                          .to_return(status: 200, body: file_fixture('commerce/salla/shipments.json').read)
  end

  it 'links the WhatsApp customer by the verified phone and shows the latest orders with tracking' do
    get path, headers: agent.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body).to include('state' => 'linked', 'store' => { 'id' => store.id, 'name' => 'Salla Demo', 'provider' => 'salla' })
    expect(body['link']).to include('match_source' => 'verified_phone')
    expect(body['orders'].pluck('order_number')).to eq(%w[30013 30012 30011 30015 30014])
    expect(body['orders'][1]).to include('status' => 'shipped', 'payment_status' => 'unknown',
                                         'tracking' => { 'number' => 'AX123456789SA',
                                                         'url' => 'https://www.aramex.com/track/results?ShipmentNumber=AX123456789SA' })
    expect(response.body).not_to include('salla-access-factory', 'salla-refresh-factory')
  end

  it 'serves cached orders marked stale while Salla is rate limiting the store' do
    get path, headers: agent.create_new_auth_token, as: :json
    orders_stub.to_return(status: 429, headers: { 'Retry-After' => '30' })

    travel(3.minutes) { get path, headers: agent.create_new_auth_token, as: :json }

    expect(response.parsed_body).to include('stale' => true, 'error' => 'RATE_LIMITED')
    expect(response.parsed_body['orders'].size).to eq(5)
  end

  it 'does not hide a revoked token behind cached data: the store needs re-authorization and its cache is dropped' do
    get path, headers: agent.create_new_auth_token, as: :json
    orders_stub.to_return(status: 401, body: '{"status":401,"success":false,"error":{"code":"Unauthorized"}}')

    travel(3.minutes) { get path, headers: agent.create_new_auth_token, as: :json }

    expect(response.parsed_body).to include('state' => 'linked', 'orders' => nil, 'error' => 'AUTH_INVALID')
    expect(store.reload).to be_needs_reauth
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload']).to eq([])
  end

  it 'asks an agent to choose when several store customers share the phone' do
    twin = JSON.parse(file_fixture('commerce/salla/customers.json').read)['data'].first.merge('id' => 1_227_534_600)
    stub_request(:get, "#{api}/customers").with(query: hash_including('keyword' => '551112233'))
                                          .to_return(respond([JSON.parse(file_fixture('commerce/salla/customers.json').read)['data'].first, twin]))

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('state' => 'multiple')
    expect(response.parsed_body['candidates'].size).to eq(2)
    expect(Commerce::CustomerLink.count).to eq(0)
  end
end
