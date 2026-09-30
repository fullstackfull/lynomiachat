require 'rails_helper'

# Responses follow the Admin GraphQL API 2026-07 schema (every queried field checked against Shopify's published schema,
# docs/commerce/19-shopify-graphql-provider.md), with this spec's own shop, customers and orders.
RSpec.describe Commerce::Providers::Shopify do
  include_context 'with commerce encryption'
  include_context 'with shopify commerce app'

  let(:graphql_url) { 'https://lynomia-demo.myshopify.com/admin/api/2026-07/graphql.json' }
  let(:store) do
    create(:commerce_store, :shopify, external_store_id: '68210001', base_url: 'https://lynomia-demo.myshopify.com',
                                      credentials: { 'access_token' => 'access-1', 'access_token_expires_at' => 1.hour.from_now.utc.iso8601,
                                                     'refresh_token' => 'refresh-1', 'refresh_token_expires_at' => 60.days.from_now.utc.iso8601,
                                                     'scope' => 'read_customers,read_orders' })
  end
  let(:provider) { described_class.new(store, credentials: store.credentials) }
  let(:customers) { JSON.parse(file_fixture('commerce/shopify/customers.json').read) }
  let(:orders) { JSON.parse(file_fixture('commerce/shopify/orders.json').read) }
  let(:guest_orders) { JSON.parse(file_fixture('commerce/shopify/guest_orders.json').read) }
  let(:operation) { ->(name) { stub_request(:post, graphql_url).with { |request| JSON.parse(request.body)['query'].include?("query #{name}(") } } }
  let(:sent) { ->(name) { a_request(:post, graphql_url).with { |request| JSON.parse(request.body)['query'].include?("query #{name}(") } } }
  let(:variables) do
    lambda do |name|
      bodies = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map { |signature| JSON.parse(signature.body) }
      bodies.select { |body| body['query'].include?("query #{name}(") }.map { |body| body['variables'] }
    end
  end

  def error_for
    yield
    nil
  rescue Commerce::Error => e
    e.as_json
  end

  it 'sends queries only, with the access token header, to the pinned API version of the store host' do
    documents = described_class.constants.map { |name| described_class.const_get(name) }.grep(String).select { |value| value.include?('{') }

    expect(documents).to all(start_with('query ').or(include('legacyResourceId')))
    expect(documents.join).not_to match(/\bmutation\b/)

    operation.call('LynomiaCustomers').to_return(status: 200, body: customers.to_json)
    provider.find_customers(phone: '+966551112233')
    expect(a_request(:post, graphql_url).with(headers: { 'X-Shopify-Access-Token' => 'access-1' })).to have_been_made.once
  end

  describe '#find_customers' do
    it 'finds the registered customer whose phone matches exactly, through a quoted phone filter' do
      operation.call('LynomiaCustomers').to_return(status: 200, body: customers.to_json)

      found = provider.find_customers(phone: '+966551112233')

      expect(found.map(&:to_h)).to eq([{ external_id: '7001', name: nil, emails: ['sara.ali@example.com'], phones: ['+966551112233'],
                                         registered: true }])
      expect(variables.call('LynomiaCustomers')).to eq([{ 'first' => 20, 'query' => 'phone:"+966551112233"' }])
      expect(sent.call('LynomiaGuestOrders')).not_to have_been_made
    end

    it 'finds the registered customer and the guest checkouts of an exact email, never a near miss' do
      operation.call('LynomiaCustomers').to_return(status: 200, body: customers.to_json)
      operation.call('LynomiaGuestOrders').to_return(status: 200, body: guest_orders.to_json)

      expect(provider.find_customers(email: ' Sara.Ali@Example.com ').map(&:external_id)).to eq(['7001'])
      expect(provider.find_customers(email: 'guest.buyer@example.com').map(&:to_h))
        .to eq([{ external_id: 'guest:guest.buyer@example.com', name: nil, emails: ['guest.buyer@example.com'], phones: [], registered: false }])
      expect(variables.call('LynomiaGuestOrders').last).to eq('first' => 20, 'query' => 'email:"guest.buyer@example.com"')
    end

    it 'finds nothing without an exact match, and never matches by name' do
      operation.call('LynomiaCustomers').to_return(status: 200, body: customers.to_json)
      operation.call('LynomiaGuestOrders').to_return(status: 200, body: guest_orders.to_json)

      expect(provider.find_customers(phone: '+966500000000')).to eq([])
      expect(provider.find_customers(email: 'nobody@example.com')).to eq([])
      expect(described_class::CUSTOMERS_QUERY).not_to match(/\b(?:firstName|lastName|displayName|name)\b/)
    end

    it 'escapes a hostile search value into one phrase inside a GraphQL variable' do
      operation.call('LynomiaCustomers').to_return(status: 200, body: { data: { customers: { nodes: [] } } }.to_json)
      operation.call('LynomiaGuestOrders').to_return(status: 200, body: { data: { orders: { nodes: [] } } }.to_json)

      provider.find_customers(email: 'x" OR email:* OR "\\@example.com')

      expect(variables.call('LynomiaCustomers')).to eq([{ 'first' => 20, 'query' => 'email:"x\" or email:* or \"\\\\@example.com"' }])
      expect(sent.call('LynomiaCustomers').with { |request| JSON.parse(request.body)['query'].include?('example.com') }).not_to have_been_made
    end
  end

  describe '#list_customer_orders' do
    it "returns the customer's newest orders, re-checked to belong to that customer" do
      operation.call('LynomiaOrders').to_return(status: 200, body: orders.to_json)

      list = provider.list_customer_orders('7001', limit: 5)

      expect(list.map(&:order_number)).to eq(%w[1006 1005 1004 1003 1002])
      expect(variables.call('LynomiaOrders')).to eq([{ 'first' => 5, 'query' => 'customer_id:7001' }])
      expect(list.map { |order| order.customer[:external_id] }.uniq).to eq(['7001'])
    end

    it "returns a guest's checkouts only: no registered customer's order with the same email" do
      operation.call('LynomiaOrders').to_return(status: 200, body: guest_orders.to_json)

      list = provider.list_customer_orders('guest:guest.buyer@example.com', limit: 5)

      expect(list.map(&:order_number)).to eq(['1010'])
      expect(variables.call('LynomiaOrders')).to eq([{ 'first' => 20, 'query' => 'email:"guest.buyer@example.com"' }])
    end

    it 'refuses a customer id that is not a Shopify customer number' do
      expect { provider.list_customer_orders('7001 OR tag:vip', limit: 5) }.to raise_error(ArgumentError)
      expect(a_request(:post, graphql_url)).not_to have_been_made
    end
  end

  describe 'order normalization' do
    let(:list) { provider.list_customer_orders('7001', limit: 6).index_by(&:order_number) }

    before { operation.call('LynomiaOrders').to_return(status: 200, body: orders.to_json) }

    it 'maps the payment status from displayFinancialStatus only' do
      expect(list.transform_values(&:payment_status)).to eq(
        '1006' => 'paid', '1005' => 'unpaid', '1004' => 'partially_refunded', '1003' => 'refunded', '1002' => 'partially_paid',
        '1001' => 'unknown'
      )
    end

    it 'maps the order status from cancellation and fulfillment only' do
      expect(list.transform_values(&:status)).to eq(
        '1006' => 'delivered', '1005' => 'processing', '1004' => 'shipped', '1003' => 'cancelled', '1002' => 'on_hold', '1001' => 'other'
      )
    end

    it 'keeps amounts, times, bounded items and the full item count' do
      order = list['1006']

      expect(order).to have_attributes(provider: 'shopify', external_order_id: '6001006', currency: 'SAR', total: '520.0',
                                       created_at: '2026-09-28T08:15:00Z', updated_at: '2026-09-28T09:15:00Z', item_count: 3,
                                       customer: { external_id: '7001', name: nil }, customer_order_url: nil)
      expect(order.items).to eq([{ name: 'Oud Perfume 50ml', quantity: 2, total: '400.0' }, { name: 'Gift Box', quantity: 1, total: '120.0' }])
      expect(described_class::ORDER_FIELDS).to include('lineItems(first: 10)', 'fulfillments(first: 10)', 'trackingInfo(first: 5)')
    end

    it 'builds the admin link from the store domain and the order number, never from the response' do
      expect(list['1006'].admin_order_url).to eq('https://lynomia-demo.myshopify.com/admin/orders/6001006')
      expect(described_class::ORDER_FIELDS).not_to include('statusPageUrl')
    end

    it 'lists every fulfillment and tracking number as a shipment, with https tracking links only' do
      expect(list['1006'].shipments.map { |shipment| shipment.slice(:provider, :status, :tracking_number) })
        .to eq([{ provider: 'Aramex', status: 'delivered', tracking_number: 'ARX100' },
                { provider: 'SMSA Express', status: 'delivered', tracking_number: 'SMSA200' }])
      expect(list['1006'].tracking).to eq(number: 'ARX100', url: 'https://www.aramex.com/track/ARX100')
      expect(list['1006'].shipping).to eq(method: 'Aramex', total: nil, provider: 'Aramex', status: 'delivered')

      expect(list['1005'].shipments.map { |shipment| shipment.slice(:tracking_number, :tracking_url, :status) })
        .to eq([{ tracking_number: 'DHL1', tracking_url: 'https://www.dhl.com/track?id=DHL1', status: 'in_transit' },
                { tracking_number: 'DHL2', tracking_url: nil, status: 'in_transit' }])
    end

    it 'shows a fulfillment without tracking by its status, with nothing to track' do
      expect(list['1004'].shipments).to eq([{ status: 'out_for_delivery', provider_status: 'out_for_delivery', type: 'shipment', provider: nil,
                                              tracking_number: nil, tracking_url: nil }])
      expect(list['1004'].tracking).to be_nil
      expect(list['1002']).to have_attributes(shipments: [], shipping: nil, tracking: nil)
    end

    it 'skips a cancelled fulfillment when choosing what to track' do
      operation.call('LynomiaOrders').to_return(status: 200, body: guest_orders.to_json)
      order = provider.list_customer_orders('guest:guest.buyer@example.com', limit: 5).sole

      expect(order.shipments.map { |shipment| shipment.slice(:status, :tracking_number) })
        .to eq([{ status: 'cancelled', tracking_number: 'ARXOLD' }, { status: 'in_transit', tracking_number: 'ARX300' }])
      expect(order.tracking).to eq(number: 'ARX300', url: 'https://www.aramex.com/track/ARX300')
      expect(order.status).to eq('shipped')
    end

    it 'refuses a malformed order instead of passing it on' do
      broken = orders.deep_dup
      broken['data']['orders']['nodes'][0].delete('currentTotalPriceSet')
      operation.call('LynomiaOrders').to_return(status: 200, body: broken.to_json)

      expect(error_for { provider.list_customer_orders('7001', limit: 5) }).to eq(code: 'INVALID_RESPONSE', reason: 'malformed_order')
    end
  end

  it 'reads one order by its number' do
    operation.call('LynomiaOrder').to_return(status: 200, body: { data: { order: orders['data']['orders']['nodes'].first } }.to_json)

    expect(provider.get_order('6001006').order_number).to eq('1006')
    expect(variables.call('LynomiaOrder')).to eq([{ 'id' => 'gid://shopify/Order/6001006' }])
  end

  describe 'protected customer data and throttling' do
    it 'reports protected customer data that is not approved, without inventing matches' do
      denied = { data: { customers: nil }, errors: [{ message: 'This app is not approved to access the Customer object.',
                                                      extensions: { code: 'ACCESS_DENIED' } }] }
      operation.call('LynomiaCustomers').to_return(status: 200, body: denied.to_json)

      expect(error_for { provider.find_customers(phone: '+966551112233') }).to eq(code: 'PROTECTED_DATA_NOT_APPROVED')
    end

    it 'finds nothing when Shopify withholds the protected fields' do
      redacted = { data: { customers: { nodes: [{ id: 'gid://shopify/Customer/7001', defaultEmailAddress: nil, defaultPhoneNumber: nil }] } } }
      operation.call('LynomiaCustomers').to_return(status: 200, body: redacted.to_json)

      expect(provider.find_customers(phone: '+966551112233')).to eq([])
    end

    it 'stops calling the store while its query budget recovers' do
      budget = { maximumAvailable: 2000.0, currentlyAvailable: 50, restoreRate: 100.0 }
      throttled = { errors: [{ message: 'Throttled', extensions: { code: 'THROTTLED' } }],
                    extensions: { cost: { requestedQueryCost: 300, throttleStatus: budget } } }
      operation.call('LynomiaCustomers').to_return(status: 200, body: throttled.to_json)

      expect(error_for { provider.find_customers(phone: '+966551112233') }).to eq(code: 'RATE_LIMITED')
      expect(error_for { provider.find_customers(phone: '+966551112233') }).to eq(code: 'RATE_LIMITED')
      expect(a_request(:post, graphql_url)).to have_been_made.once
      expect(Redis::Alfred.ttl('COMMERCE::SHOPIFY::MERCHANT::68210001::BACKOFF')).to be_between(1, 3)
    end

    it 'pauses before the budget runs out, from the cost Shopify reports' do
      low = customers.deep_merge('extensions' => { 'cost' => { 'requestedQueryCost' => 42, 'throttleStatus' => { 'currentlyAvailable' => 12 } } })
      operation.call('LynomiaCustomers').to_return(status: 200, body: low.to_json)

      expect(provider.find_customers(phone: '+966551112233').size).to eq(1)
      expect(error_for { provider.find_customers(phone: '+966551112233') }).to eq(code: 'RATE_LIMITED')
      expect(a_request(:post, graphql_url)).to have_been_made.once
    end
  end

  it 'refreshes a rejected token once and retries the query' do
    stub_request(:post, 'https://lynomia-demo.myshopify.com/admin/oauth/access_token')
      .to_return(status: 200, body: { access_token: 'access-2', refresh_token: 'refresh-2', scope: 'read_customers,read_orders', expires_in: 3600,
                                      refresh_token_expires_in: 7_776_000 }.to_json)
    stub_request(:post, graphql_url).with(headers: { 'X-Shopify-Access-Token' => 'access-1' }).to_return(status: 401, body: '{"errors":"Invalid"}')
    stub_request(:post, graphql_url).with(headers: { 'X-Shopify-Access-Token' => 'access-2' }).to_return(status: 200, body: customers.to_json)

    expect(provider.find_customers(phone: '+966551112233').map(&:external_id)).to eq(['7001'])
    expect(store.reload.credentials['access_token']).to eq('access-2')
  end

  it 'confirms the token belongs to this shop' do
    stub_request(:post, graphql_url).to_return(status: 200, body: file_fixture('commerce/shopify/shop.json').read)
    expect(provider.health).to be(true)

    store.update!(external_store_id: '99')
    expect(error_for { described_class.new(store, credentials: store.credentials).health }).to eq(code: 'AUTH_INVALID')
  end
end
