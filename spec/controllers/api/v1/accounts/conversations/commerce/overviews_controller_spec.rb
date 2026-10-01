require 'rails_helper'

# Customer 360 (docs/commerce/25-customer-360.md) over one contact linked in a WooCommerce, a Salla, a Zid and a Shopify
# store. Figures are those of the orders the stores return (fixtures), aggregated without conversion or guessing.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Customer 360 overview', type: :request do
  include_context 'with four commerce stores'

  let(:overview_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/overview" }
  let(:overview) do
    lambda do |user = agent|
      get overview_path, headers: user.create_new_auth_token, as: :json
      response.parsed_body
    end
  end
  let(:store_entry) { ->(body, store) { body['stores'].find { |entry| entry['store']['id'] == store.id } } }

  it 'aggregates every store of the contact: counts, paid spend per currency, last purchase and the newest orders across stores' do
    body = overview.call

    expect(response).to have_http_status(:ok)
    expect(body).to include('contact' => { 'id' => contact.id }, 'stores_count' => 4, 'linked_stores_count' => 4, 'orders_count_visible' => 16,
                            'currencies' => ['SAR'], 'active_orders_count' => 9, 'shipped_orders_count' => 3, 'partial' => false,
                            'last_order_at' => '2026-09-29T07:15:00Z')
    # Paid only: WooCommerce #24, Zid 41000102 and Shopify #1006. Salla reports no payment confirmation, so none counts.
    expect(body['total_spend_visible']).to eq([{ 'currency' => 'SAR', 'amount' => '843.56000086523' }])

    latest = body['latest_orders']
    expect(latest.size).to eq(10)
    expect(latest.pluck('created_at')).to eq(latest.pluck('created_at').sort.reverse)
    expect(latest.first).to include('order_number' => '41000102', 'store' => { 'id' => zid.id, 'name' => 'Zid Store', 'provider' => 'zid' })
    expect(latest.map { |order| order['store']['provider'] }.uniq).to contain_exactly('woocommerce', 'salla', 'zid', 'shopify')
    expect(latest).to all(satisfy { |order| order['provider'] == order['store']['provider'] && !order.key?('customer') })

    expect(body['stores'].map { |entry| entry.values_at('state', 'orders_count') })
      .to eq([['linked', 3], ['linked', 5], ['linked', 3], ['linked', 5]])
    expect(body['stores'].map { |entry| entry['link']['customer_type'] }).to eq(%w[guest registered registered registered])
    expect(body['stores']).to all(include('fetched_at' => be_present, 'stale' => false, 'error' => nil))
    expect(response.body).not_to include('+966551112233', '551112233', 'external_id', 'candidates', 'token')
  end

  it 'keeps currencies apart and never converts them' do
    usd = woo_orders.values_at(25, 24, 23).map { |order| order['id'] == 24 ? order.merge('currency' => 'USD') : order }
    woo_search.to_return(status: 200, body: usd.to_json)

    body = overview.call

    expect(body['currencies']).to eq(%w[SAR USD])
    expect(body['total_spend_visible']).to eq([{ 'currency' => 'SAR', 'amount' => '743.56000086523' }, { 'currency' => 'USD', 'amount' => '100.0' }])
  end

  it 'answers with the other stores when one cannot be read, and reports which one' do
    stub_request(:post, shopify_graphql).to_return(status: 503)

    body = overview.call

    expect(response).to have_http_status(:ok)
    expect(store_entry.call(body, shopify)).to include('state' => 'unavailable', 'orders_count' => nil, 'error' => 'STORE_UNAVAILABLE')
    expect(body).to include('partial' => true, 'orders_count_visible' => 11, 'linked_stores_count' => 3)
    expect(body['latest_orders'].map { |order| order['store']['provider'] }).not_to include('shopify')
  end

  it 'keeps each store\'s own freshness, and serves a store\'s cached orders as stale during its outage' do
    overview.call
    stub_request(:get, "#{salla_api}/orders").with(query: hash_including('customer_id' => '1227534533')).to_return(status: 503)

    body = travel(3.minutes) { overview.call }

    expect(store_entry.call(body, salla)).to include('stale' => true, 'error' => 'STORE_UNAVAILABLE', 'orders_count' => 5)
    [woo, zid, shopify].each do |store|
      expect(store_entry.call(body, store)).to include('stale' => false, 'error' => nil)
      expect(Time.iso8601(store_entry.call(body, store)['fetched_at']) - Time.iso8601(store_entry.call(body, salla)['fetched_at'])).to be >= 3.minutes
    end
    expect(body).to include('partial' => true, 'orders_count_visible' => 16)
  end

  it 'never shows a store whose credentials were rejected, and stops reading it' do
    overview.call
    stub_request(:get, zid_orders).with(query: hash_including('customer_id' => '90001'))
                                  .to_return(status: 401, body: '{"status":401,"success":false}')
    stub_request(:post, 'https://oauth.zid.sa/oauth/token').to_return(status: 400, body: '{"error":"invalid_grant"}')

    expect(store_entry.call(travel(3.minutes) { overview.call }, zid)).to include('orders_count' => nil, 'error' => 'AUTH_INVALID')
    expect(zid.reload).to be_needs_reauth

    WebMock.reset_executed_requests!
    body = overview.call
    expect(store_entry.call(body, zid)).to include('state' => 'needs_reauth', 'orders_count' => nil)
    expect(a_request(:any, /api\.zid\.sa/)).not_to have_been_made
    expect(body['latest_orders'].map { |order| order['store']['provider'] }).not_to include('zid')
  end

  it 'does not read a store whose provider is switched off, nor show its cached orders' do
    overview.call
    InstallationConfig.find_by!(name: 'ZID_ENABLED').update!(value: false)
    GlobalConfig.clear_cache
    WebMock.reset_executed_requests!

    body = overview.call

    expect(store_entry.call(body, zid)).to include('state' => 'provider_unavailable', 'orders_count' => nil)
    expect(a_request(:any, /zid\.sa/)).not_to have_been_made
    expect(body).to include('orders_count_visible' => 13)
  end

  it 'answers within its time budget when a store is too slow, without that store' do
    stub_const('Commerce::Customer360::STORE_TIMEOUT', 0.5)
    stub_request(:get, "#{salla_api}/orders").with(query: hash_including('customer_id' => '1227534533')).to_return do
      sleep 1.5
      salla_envelope.call(salla_orders)
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    body = overview.call

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1.5
    expect(store_entry.call(body, salla)).to include('state' => 'unavailable', 'error' => 'TIMEOUT')
    expect(body['orders_count_visible']).to eq(11)
    sleep 1.5 # let the slow store's thread finish inside the example
  end

  it 'shows a store where the contact is not linked without its candidates' do
    stub_request(:get, "#{salla_api}/customers").with(query: hash_including('keyword' => '551112233')).to_return(salla_envelope.call([]))

    entry = store_entry.call(overview.call, salla)

    expect(entry).to include('state' => 'not_found', 'link' => nil, 'orders_count' => nil)
    expect(entry).not_to have_key('candidates')
  end

  it 'answers an account without stores' do
    [woo, salla, zid, shopify].each(&:destroy!)

    expect(overview.call).to include('stores_count' => 0, 'linked_stores_count' => 0, 'orders_count_visible' => 0, 'last_order_at' => nil,
                                     'total_spend_visible' => [], 'latest_orders' => [], 'stores' => [], 'partial' => false)
  end

  describe 'access' do
    it 'is refused without Commerce, to agents who cannot see the conversation, and to other accounts' do
      outsider = create(:user, account: account, role: :agent)
      other = create(:user, account: create(:account), role: :administrator)

      overview.call(outsider)
      expect(response).to have_http_status(:unauthorized)
      overview.call(other)
      expect(response).to have_http_status(:unauthorized)
      account.disable_features!('lynomia_commerce')
      overview.call
      expect(response).to have_http_status(:unauthorized)
      expect(a_request(:any, /shop\.example|salla|zid|myshopify/)).not_to have_been_made
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
