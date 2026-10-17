require 'rails_helper'

# The conversation panel with a Store Syria store: the same API, matcher and cache as the other four, nothing
# Store-Syria-specific. What this proves is that the fifth provider needed no second path -- a conversation on a
# WhatsApp channel finds its shopper by the phone the channel verified, and their orders come back in the canonical
# vocabulary with the store's own words kept alongside.
RSpec.describe 'Conversation commerce API with a Store Syria store', type: :request do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp.inbox }
  let(:contact) { create(:contact, account: account, name: 'Omar', email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '963955111222') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:store) do
    create(:commerce_store, account: account, provider: 'storesyria', name: 'متجر دمشق',
                            base_url: 'https://storesyria.test', external_store_id: 'storesyria.test:4',
                            credentials: { 'commerce_token' => "lsc_4_1_#{'a' * 64}" })
  end
  let(:api) { 'https://storesyria.test/api/lynomia/commerce/v1' }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores/#{store.id}" }
  let(:lookup) { stub_request(:post, "#{api}/customers/lookup") }
  let(:customer) do
    { 'id' => '4', 'name' => 'Omar Haddad', 'emails' => [], 'phones' => ['0955111222'], 'phone_region' => 'SY', 'guest' => false }
  end
  let(:order) do
    { 'id' => '55', 'number' => 'A-1', 'delivered_status' => 5, 'status_label' => 'Picked Up', 'payment_status' => 'paid',
      'currency' => 'SYP', 'total' => '1500.50', 'created_at' => '2026-01-01T12:00:00Z', 'items' => [], 'item_count' => 2,
      'shipping' => { 'method' => nil, 'total' => '0.00', 'carrier' => nil }, 'tracking_number' => nil }
  end

  def json(body) = { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }

  before do
    account.enable_features!('lynomia_commerce')
    create(:inbox_member, inbox: inbox, user: agent)
    allow(Resolv).to receive(:getaddresses).with('storesyria.test').and_return(['93.184.216.70'])
    GlobalConfig.clear_cache
    create(:installation_config, name: 'STORESYRIA_ENABLED', value: true)
    GlobalConfig.clear_cache
    Commerce::Cache.purge(store)
  end

  it 'is offered alongside the other providers once the installation turns it on' do
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores",
        headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['payload']).to contain_exactly(
      hash_including('id' => store.id, 'provider' => 'storesyria', 'linked' => false, 'actions' => false, 'carts' => false)
    )
  end

  # CARTS ARE OFF, AND THE REASON IS WRITTEN DOWN RATHER THAN ACCIDENTAL. The adapter reports carts
  # (supports_carts? is true), but recovery is a separate decision: Store Syria is in the recovery
  # switch table with its own key defaulting to off, and in PRE_UAT, so no installation can turn it
  # on until it has passed a real UAT -- and the consent model it needs does not exist until 3E.
  it 'keeps abandoned-cart recovery off behind its own switch and the pre-UAT gate' do
    expect(Commerce::Providers::Storesyria).to be_supports_carts
    expect(Commerce::Switches::RECOVERY_KEYS).to include('storesyria' => 'STORESYRIA_RECOVERY_ENABLED')
    expect(Commerce::Switches::PRE_UAT[:recovery]).to include('storesyria')

    GlobalConfig.clear_cache
    create(:installation_config, name: 'STORESYRIA_RECOVERY_ENABLED', value: true)
    GlobalConfig.clear_cache

    # Even switched on, the pre-UAT gate keeps it off: a provider leaves PRE_UAT through a
    # reviewed code change, not through a setting.
    expect(Commerce::AbandonedCarts.offered?(store)).to be(false)
  end

  # The WhatsApp source id is a phone the CHANNEL verified, so one shopper who really carries it is a match rather
  # than a suggestion, and the agent is never asked to pick from a name search -- which the contract does not expose.
  it 'links the shopper found by the phone the channel verified' do
    lookup.to_return(json(data: [customer]))
    stub_request(:get, "#{api}/customers/4/orders").with(query: hash_including({})).to_return(json(data: []))

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('state' => 'linked')
    expect(response.parsed_body['link']).to include('match_source' => 'verified_phone', 'customer_type' => 'registered')
    # The national significant number, because the store keeps "+963955111222" and "0955111222" for one person.
    expect(a_request(:post, "#{api}/customers/lookup").with(body: { phone: '955111222' }.to_json)).to have_been_made
  end

  # Lynomia refuses to guess a region for a local number, so a store that names none matches nobody -- a customer
  # not found rather than the wrong customer found. Nothing is linked and nothing is fetched.
  it 'links nobody when the store reports a local number with no region' do
    lookup.to_return(json(data: [customer.except('phone_region')]))

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('state' => 'not_found')
    expect(a_request(:get, %r{/customers/4/orders})).not_to have_been_made
  end

  it 'shows the linked shopper\'s orders in the canonical vocabulary, keeping the store\'s own word' do
    create(:commerce_customer_link, store: store, contact: contact, external_customer_id: '4')
    stub_request(:get, "#{api}/customers/4/orders").with(query: hash_including({})).to_return(json(data: [order]))

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['state']).to eq('linked')
    row = response.parsed_body['orders'].sole
    expect(row).to include('order_number' => 'A-1', 'payment_status' => 'paid', 'currency' => 'SYP', 'total' => '1500.5')
    # 'Picked Up' canonicalises to processing -- the parcel has not left the store -- and the raw word survives
    # because a merchant who ships from a warehouse cares about the difference.
    expect(row).to include('status' => 'processing', 'provider_status' => 'Picked Up')
    # delivered_status 5 is a shipment that exists but has not moved; nothing invents a tracking number.
    expect(row['shipments'].sole).to include('status' => 'pending', 'tracking_number' => nil)
    expect(row['tracking']).to be_nil
    expect(row['admin_order_url']).to eq('https://storesyria.test/order/55')
  end

  it 'reports the store as unavailable rather than emptying the panel when it cannot be read' do
    create(:commerce_customer_link, store: store, contact: contact, external_customer_id: '4')
    stub_request(:get, "#{api}/customers/4/orders").with(query: hash_including({})).to_return(status: 500, body: '{}')

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('state' => 'linked', 'orders' => nil)
    expect(response.parsed_body['error']).to be_present
  end

  # Read-only, and the panel says so: nothing in it offers an action, because the contract exposes none.
  it 'offers no order actions, whatever the agent\'s role' do
    administrator = create(:user, account: account, role: :administrator)
    create(:inbox_member, inbox: inbox, user: administrator)
    store.update!(settings: store.settings.merge('order_actions' => true))

    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores",
        headers: administrator.create_new_auth_token, as: :json

    expect(response.parsed_body['payload'].sole['actions']).to be(false)
  end
end
