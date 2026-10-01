require 'rails_helper'

# Order search by number (docs/commerce/25-customer-360.md §order search): each store is asked for the number directly,
# never scanned; the orders come back without their customer, whoever they belong to.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Commerce order search', type: :request do
  include_context 'with four commerce stores'

  let(:orders_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/orders" }
  let(:search) do
    lambda do |number, store_id: nil, user: agent|
      get orders_path, params: { number: number, store_id: store_id }.compact, headers: user.create_new_auth_token, as: :json
      response.parsed_body
    end
  end
  let(:zid_view) { ->(id) { "#{zid_orders}/#{id}/view" } }
  let(:shopify_names) do
    lambda do |name|
      stub_request(:post, shopify_graphql).with do |request|
        body = JSON.parse(request.body)
        body['query'].include?('query LynomiaOrders(') && body['variables']['query'] == %(name:"#{name}")
      end
    end
  end

  before do
    Redis::Alfred.scan_each(match: "COMMERCE::ORDER_SEARCH::ACCOUNT::#{account.id}::*") { |key| Redis::Alfred.delete(key) }
    stub_request(:get, %r{\A#{Regexp.escape(woo_api)}/orders/\d+\z}).to_return(status: 404, body: '{"code":"woocommerce_rest_shop_order_invalid_id"}')
    stub_request(:get, %r{\A#{Regexp.escape(zid_orders)}/\d+/view\z}).to_return(status: 404, body: '{"status":404}')
  end

  it 'asks every store for the number, reports Salla as not searchable, and leaves the customer out' do
    stub_request(:get, "#{woo_api}/orders/26").to_return(status: 200, body: woo_orders[26].to_json)
    shopify_names.call('26').to_return(status: 200, body: { data: { orders: { nodes: [] } } }.to_json)

    body = search.call('#26')

    expect(response).to have_http_status(:ok)
    expect(body['orders'].sole).to include('order_number' => '26', 'provider' => 'woocommerce',
                                           'store' => { 'id' => woo.id, 'name' => 'Woo Store', 'provider' => 'woocommerce' })
    expect(body['orders'].sole).not_to have_key('customer')
    expect(body['stores'].map { |entry| entry.values_at('state', 'error') })
      .to eq([['searched', nil], ['unsupported', nil], ['searched', nil], ['searched', nil]])
    expect(body['partial']).to be(false)
    expect(response.body).not_to include('Sara', 'billing', 'email', 'phone')
    expect(a_request(:get, /api\.salla\.dev/)).not_to have_been_made
    expect(a_request(:get, %r{wc/v3/orders\?})).not_to have_been_made
    expect(Commerce::CustomerLink.count).to eq(0)
  end

  it 'returns every store\'s order with that number, newest first, keeping only exact matches' do
    stub_request(:get, "#{woo_api}/orders/1006").to_return(status: 200, body: woo_orders[22].merge('id' => 1006, 'number' => '1006').to_json)
    stub_request(:get, zid_view.call(1006)).to_return(status: 200, body: { order: zid_fixture['orders'].first.merge('id' => 1006) }.to_json)
    shopify_names.call('1006').to_return(status: 200, body: file_fixture('commerce/shopify/orders.json').read)

    body = search.call('1006')

    expect(body['orders'].map { |order| order.values_at('provider', 'order_number') })
      .to contain_exactly(%w[woocommerce 1006], %w[zid 1006], %w[shopify 1006])
    expect(body['orders'].pluck('created_at')).to eq(body['orders'].pluck('created_at').sort.reverse)
  end

  it 'searches one store only when asked to' do
    stub_request(:get, zid_view.call(41_000_102)).to_return(status: 200, body: { order: zid_fixture['orders'].first }.to_json)

    body = search.call('41000102', store_id: zid.id)

    expect(body['orders'].pluck('order_number')).to eq(['41000102'])
    expect(body['stores'].pluck('store').pluck('id')).to eq([zid.id])
    expect(a_request(:any, /shop\.example|salla|myshopify/)).not_to have_been_made
  end

  it 'refuses anything but an order number, before any store is asked' do
    ['', 'abc', '12a', '1 OR 1', '1" OR name:*', '"1"', '##1', '-1', '1' * 21, "1\n2"].each do |number|
      search.call(number)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('error', 'code')).to eq('INVALID_QUERY')
    end
    expect(a_request(:any, /shop\.example|salla|zid|myshopify/)).not_to have_been_made
  end

  it 'answers with the other stores when one cannot be read, and flags a store whose keys stop working' do
    stub_request(:get, zid_view.call(26)).to_return(status: 503)
    stub_request(:get, "#{woo_api}/orders/26").to_return(status: 401)
    shopify_names.call('26').to_return(status: 200, body: { data: { orders: { nodes: [] } } }.to_json)

    body = search.call('26')

    expect(response).to have_http_status(:ok)
    expect(body['stores'].map { |entry| entry.values_at('state', 'error') })
      .to eq([%w[unavailable AUTH_INVALID], ['unsupported', nil], %w[unavailable STORE_UNAVAILABLE], ['searched', nil]])
    expect(body['partial']).to be(true)
    expect(woo.reload).to be_needs_reauth
  end

  it 'allows each agent SEARCH_LIMIT searches a minute' do
    shopify_names.call('7').to_return(status: 200, body: { data: { orders: { nodes: [] } } }.to_json)
    other_agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: whatsapp.inbox, user: other_agent)

    10.times { search.call('7') }
    expect(response).to have_http_status(:ok)
    WebMock.reset_executed_requests!

    body = search.call('7')
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers['Retry-After'].to_i).to be_between(1, 60)
    expect(body.dig('error', 'code')).to eq('RATE_LIMITED')
    expect(a_request(:any, /shop\.example|zid|myshopify/)).not_to have_been_made

    search.call('7', user: other_agent)
    expect(response).to have_http_status(:ok)
  end

  it 'audits each search with its number and counts' do
    skip 'Enterprise audit log not loaded' unless defined?(Enterprise::AuditLog)
    shopify_names.call('26').to_return(status: 200, body: { data: { orders: { nodes: [] } } }.to_json)
    stub_request(:get, "#{woo_api}/orders/26").to_return(status: 200, body: woo_orders[26].to_json)

    search.call('26')

    expect(Enterprise::AuditLog.where(comment: 'commerce.orders_searched').sole)
      .to have_attributes(user_id: agent.id, audited_changes: { 'number' => '26', 'stores' => 4, 'orders' => 1 })
  end

  describe 'access' do
    it 'is refused without Commerce, to agents who cannot see the conversation, and to other accounts' do
      outsider = create(:user, account: account, role: :agent)
      other = create(:user, account: create(:account), role: :administrator)

      search.call('26', user: outsider)
      expect(response).to have_http_status(:unauthorized)
      search.call('26', user: other)
      expect(response).to have_http_status(:unauthorized)
      account.disable_features!('lynomia_commerce')
      search.call('26')
      expect(response).to have_http_status(:unauthorized)
      expect(a_request(:any, /shop\.example|salla|zid|myshopify/)).not_to have_been_made
    end

    it 'does not search another account\'s store, a disabled store, or a store of a provider switched off' do
      foreign = create(:commerce_store, account: create(:account))
      InstallationConfig.find_by!(name: 'ZID_ENABLED').update!(value: false)
      GlobalConfig.clear_cache
      woo.update!(status: :disabled)

      [foreign, zid, woo].each do |store|
        search.call('26', store_id: store.id)
        expect(response).to have_http_status(:not_found)
      end
      shopify_names.call('26').to_return(status: 200, body: { data: { orders: { nodes: [] } } }.to_json)
      expect(search.call('26')['stores'].pluck('store').pluck('provider')).to eq(%w[salla shopify])
      expect(a_request(:any, /shop\.example|zid/)).not_to have_been_made
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
