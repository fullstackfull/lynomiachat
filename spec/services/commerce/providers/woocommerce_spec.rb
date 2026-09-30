require 'rails_helper'

# Responses are real WooCommerce 10.9.4 payloads captured from the E2E test store (docs/commerce/09-woocommerce-e2e.md).
RSpec.describe Commerce::Providers::Woocommerce do
  let(:store) { build(:commerce_store, base_url: 'https://shop.example.com', external_store_id: 'shop.example.com') }
  let(:provider) { described_class.new(store, credentials: { 'consumer_key' => 'ck_key', 'consumer_secret' => 'cs_secret' }) }
  let(:api) { 'https://shop.example.com/wp-json/wc/v3' }
  let(:orders) { JSON.parse(file_fixture('commerce/woocommerce/orders.json').read) }
  let(:customers) { JSON.parse(file_fixture('commerce/woocommerce/customers.json').read) }

  def orders_with(*ids)
    ids.map { |id| orders.find { |order| order['id'] == id } }
  end

  def stub_orders(query, body)
    stub_request(:get, "#{api}/orders").with(query: hash_including(query)).to_return(status: 200, body: body.to_json)
  end

  def error_for
    yield
    nil
  rescue Commerce::Error => e
    e.as_json
  end

  before { allow(Resolv).to receive(:getaddresses).with('shop.example.com').and_return(['93.184.216.34']) }

  describe '#health' do
    it 'checks the wc/v3 API and read access to orders and customers' do
      stub_request(:get, "#{api}?_fields=namespace").to_return(status: 200, body: file_fixture('commerce/woocommerce/namespace.json').read)
      orders_stub = stub_orders({ 'per_page' => '1' }, [{ id: 22 }])
      customers_stub = stub_request(:get, "#{api}/customers").with(query: hash_including('role' => 'all')).to_return(status: 200, body: '[{"id":2}]')

      expect(provider.health).to be(true)
      expect([orders_stub, customers_stub]).to all(have_been_requested.once)
    end

    it 'rejects a site without the WooCommerce REST API' do
      stub_request(:get, "#{api}?_fields=namespace").to_return(status: 404, body: '{"code":"rest_no_route"}')

      expect(error_for { provider.health }).to eq(code: 'STORE_UNAVAILABLE', reason: 'woocommerce_api_not_found')
    end

    it 'reports invalid keys' do
      stub_request(:get, "#{api}?_fields=namespace")
        .to_return(status: 401, body: '{"code":"woocommerce_rest_authentication_error","message":"Consumer secret is invalid."}')

      expect(error_for { provider.health }).to eq(code: 'AUTH_INVALID')
    end

    it 'reports keys whose user cannot read orders' do
      stub_request(:get, "#{api}?_fields=namespace").to_return(status: 200, body: '{"namespace":"wc/v3"}')
      stub_request(:get, "#{api}/orders").with(query: hash_including('per_page' => '1'))
                                         .to_return(status: 403, body: '{"code":"woocommerce_rest_cannot_view"}')

      expect(error_for { provider.health }).to eq(code: 'PERMISSION_DENIED')
    end

    it 'rejects an HTML page answering on the API path' do
      stub_request(:get, "#{api}?_fields=namespace").to_return(status: 200, body: '<html>maintenance</html>')

      expect(error_for { provider.health }).to eq(code: 'INVALID_RESPONSE', reason: 'not_json')
    end
  end

  it 'identifies the store by the host and path it was connected with, not by anything the store claims' do
    expect(provider.store_identity).to eq(external_store_id: 'shop.example.com', name: 'shop.example.com')
  end

  describe '#find_customers' do
    it 'finds a guest by an exact E.164 match of a locally formatted billing phone' do
      stub_orders({ 'search' => '551112233' }, orders_with(25, 24, 23))

      expect(provider.find_customers(phone: '+966551112233')).to contain_exactly(
        have_attributes(external_id: 'guest:+966551112233', name: 'Omar Khalil', emails: ['omar.khalil@example.com'], registered: false)
      )
    end

    it 'drops search hits that only contain the digits' do
      near_miss = orders_with(25).first.deep_merge('billing' => { 'phone' => '+97155111223344' }, 'shipping' => { 'phone' => '' })
      stub_orders({ 'search' => '551112233' }, [near_miss])

      expect(provider.find_customers(phone: '+966551112233')).to eq([])
    end

    it 'returns every customer sharing a phone so an agent chooses' do
      stub_orders({ 'search' => '550000111' }, orders_with(26, 27))

      expect(provider.find_customers(phone: '+966550000111').map(&:external_id)).to contain_exactly('3', '4')
    end

    it 'returns every customer sharing a billing email so an agent chooses' do
      stub_request(:get, "#{api}/customers").with(query: hash_including('email' => 'family@example.com')).to_return(status: 200, body: '[]')
      stub_orders({ 'search' => 'family@example.com' }, orders_with(28, 29))

      expect(provider.find_customers(email: 'family@example.com').map(&:external_id)).to contain_exactly('5', '6')
    end

    it 'matches emails case-insensitively and merges the account with its orders' do
      layla = customers.select { |customer| customer['id'] == 2 }
      stub_request(:get, "#{api}/customers").with(query: hash_including('email' => 'layla.haddad@example.com'))
                                            .to_return(status: 200, body: layla.to_json)
      stub_orders({ 'search' => 'layla.haddad@example.com' }, orders_with(22, 20))

      expect(provider.find_customers(email: ' Layla.Haddad@Example.com ')).to contain_exactly(
        have_attributes(external_id: '2', name: 'ليلى حداد', phones: ['+966501234567'], registered: true)
      )
    end

    it 'returns nothing when the store has no such customer' do
      stub_request(:get, "#{api}/customers").with(query: hash_including('email' => 'nobody@example.com')).to_return(status: 200, body: '[]')
      stub_orders({ 'search' => 'nobody@example.com' }, [])

      expect(provider.find_customers(email: 'nobody@example.com')).to eq([])
    end

    it 'does not search with a phone number it cannot parse' do
      expect(provider.find_customers(phone: '12345')).to eq([])
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end

  describe '#list_customer_orders' do
    it 'returns a registered customer\'s latest orders, normalized' do
      stub = stub_orders({ 'customer' => '2', 'per_page' => '5', 'orderby' => 'date', 'order' => 'desc' }, orders_with(22, 20, 18, 17, 16))

      result = provider.list_customer_orders('2', limit: 5)

      expect(stub).to have_been_requested.once
      expect(result.map { |order| [order.order_number, order.status, order.payment_status] }).to eq(
        [%w[22 processing unknown], %w[20 completed partially_refunded], %w[18 refunded refunded], %w[17 on_hold unknown], %w[16 cancelled unknown]]
      )
    end

    it 'returns a guest\'s orders re-checked against the exact identifier' do
      other_guest = orders_with(23).first.deep_merge('id' => 99, 'billing' => { 'email' => 'someone.else@example.com', 'phone' => '0551112234' },
                                                     'shipping' => { 'phone' => '' })
      stub_orders({ 'search' => '551112233', 'customer' => '0' }, orders_with(25, 24) + [other_guest])

      expect(provider.list_customer_orders('guest:+966551112233', limit: 5).map(&:order_number)).to eq(%w[25 24])
    end

    it 'returns an empty list for a customer without orders' do
      stub_orders({ 'customer' => '7' }, [])

      expect(provider.list_customer_orders('7', limit: 5)).to eq([])
    end
  end

  describe '#normalize_order' do
    it 'normalizes a paid, shipped, multi-item order' do
      order = provider.normalize_order(orders_with(14).first)

      expect(order.as_json).to eq(
        'provider' => 'woocommerce', 'external_order_id' => '14', 'order_number' => '14', 'status' => 'completed',
        'provider_status' => 'completed', 'payment_status' => 'paid', 'currency' => 'SAR', 'total' => '316.00',
        'created_at' => '2026-08-31T08:36:53Z', 'updated_at' => '2026-09-30T08:36:55Z',
        'items' => [{ 'name' => 'سيروم الورد للوجه', 'quantity' => 1, 'total' => '120.00' },
                    { 'name' => 'Argan Hair Oil', 'quantity' => 2, 'total' => '171.00' }],
        'item_count' => 3, 'customer' => { 'external_id' => '2', 'name' => 'ليلى حداد' },
        'shipping' => { 'method' => 'Aramex Express', 'total' => '25.00' }, 'shipments' => [], 'tracking' => nil,
        'admin_order_url' => 'https://shop.example.com/wp-admin/admin.php?action=edit&id=14&page=wc-orders', 'customer_order_url' => nil
      )
    end

    it 'ignores plugin tracking metadata and the store-supplied links' do
      raw = orders_with(14).first
      expect(raw['meta_data'].to_json).to include('_wc_shipment_tracking_items')

      order = provider.normalize_order(raw.merge('_links' => { 'self' => [{ 'href' => 'https://evil.example/wp-admin' }] }))

      expect(order.tracking).to be_nil
      expect(order.admin_order_url).to start_with('https://shop.example.com/wp-admin/')
    end

    it 'has no shipping for a virtual-only order' do
      order = provider.normalize_order(orders_with(24).first)

      expect([order.shipping, order.payment_status]).to eq([nil, 'paid'])
    end

    {
      15 => %w[processing paid], 23 => %w[pending unpaid], 25 => %w[failed failed], 22 => %w[processing unknown],
      17 => %w[on_hold unknown], 16 => %w[cancelled unknown], 18 => %w[refunded refunded], 20 => %w[completed partially_refunded]
    }.each do |id, (status, payment_status)|
      it "derives #{payment_status} for order #{id} (#{status})" do
        order = provider.normalize_order(orders_with(id).first)

        expect([order.status, order.payment_status]).to eq([status, payment_status])
      end
    end

    it 'never reports paid without a payment date' do
      raw = orders_with(15).first.merge('date_paid_gmt' => nil, 'date_paid' => nil)

      expect(provider.normalize_order(raw).payment_status).to eq('unknown')
    end

    it 'maps unknown statuses to other and keeps the provider status' do
      order = provider.normalize_order(orders_with(15).first.merge('status' => 'shipped'))

      expect([order.status, order.provider_status, order.payment_status]).to eq(%w[other shipped unknown])
    end

    [
      ->(raw) { raw.except('status') }, ->(raw) { raw.merge('total' => 'lots') }, ->(raw) { raw.merge('line_items' => nil) },
      ->(raw) { raw.merge('id' => 'x') }, ->(raw) { raw.merge('date_created_gmt' => 'yesterday') }
    ].each_with_index do |mutation, index|
      it "raises INVALID_RESPONSE for malformed order ##{index + 1}" do
        expect(error_for do
          provider.normalize_order(mutation.call(orders_with(14).first))
        end).to eq(code: 'INVALID_RESPONSE', reason: 'malformed_order')
      end
    end
  end

  it 'raises INVALID_RESPONSE when a list endpoint does not return a list' do
    stub_orders({ 'customer' => '2' }, { 'orders' => [] })

    expect(error_for { provider.list_customer_orders('2', limit: 5) }).to eq(code: 'INVALID_RESPONSE', reason: 'unexpected_shape')
  end

  it 'builds admin order URLs only from the store URL and a numeric id' do
    expect(provider.admin_order_url('17')).to eq('https://shop.example.com/wp-admin/admin.php?action=edit&id=17&page=wc-orders')
    expect { provider.admin_order_url('17/../../x') }.to raise_error(ArgumentError)
    expect { provider.admin_order_url('0') }.to raise_error(ArgumentError)
  end

  it 'exposes no write operation' do
    expect(described_class.public_instance_methods(false)).to contain_exactly(
      :health, :store_identity, :find_customers, :list_customer_orders, :get_order, :admin_order_url, :normalize_customer, :normalize_order
    )
  end
end
