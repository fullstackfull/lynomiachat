require 'rails_helper'

# Responses follow Zid's documented shapes: the orders fixture is built from the official Zid Python SDK's recorded
# fixtures (github.com/zidsa/sdk-python, tests/fixtures), with this spec's own customers.
RSpec.describe Commerce::Providers::Zid do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:orders_url) { 'https://api.zid.sa/v1/managers/store/orders' }
  let(:store) { create(:commerce_store, :zid, external_store_id: '318001', metadata: { 'time_zone' => 'Asia/Riyadh' }) }
  let(:provider) { described_class.new(store, credentials: store.credentials) }
  let(:orders) { JSON.parse(file_fixture('commerce/zid/orders.json').read) }
  let(:headers) { { 'Authorization' => 'Bearer zid-authorization-factory', 'X-Manager-Token' => 'zid-manager-factory' } }

  def respond(list, headers = {})
    { status: 200, body: orders.merge('orders' => list).to_json, headers: headers }
  end

  def error_for
    yield
    nil
  rescue Commerce::Error => e
    e.as_json
  end

  describe '#find_customers' do
    it "searches the orders by the national number and keeps only the exact E.164 mobile of a customer's order" do
      search = stub_request(:get, orders_url).with(query: { 'search_term' => '551112233', 'per_page' => '20', 'payload_type' => 'default' },
                                                   headers: headers).to_return(respond(orders['orders']))

      found = provider.find_customers(phone: '+966551112233')

      expect(found.map(&:to_h)).to eq([{ external_id: '90001', name: 'Sara Ali', emails: ['sara.ali@example.com'], phones: ['+966551112233'],
                                         registered: true }])
      expect(search).to have_been_requested.once
    end

    it 'matches an email exactly and case-insensitively, and never by name' do
      stub_request(:get, orders_url).with(query: hash_including('search_term' => 'sara.ali@example.com')).to_return(respond(orders['orders']))
      stub_request(:get, orders_url).with(query: hash_including('search_term' => 'sara@example.com')).to_return(respond(orders['orders']))

      expect(provider.find_customers(email: ' Sara.Ali@Example.COM ').map(&:external_id)).to eq(['90001'])
      expect(provider.find_customers(email: 'sara@example.com')).to eq([])
    end

    it 'never takes an identity from a marketplace order or a masked value' do
      masked = orders['orders'].find { |raw| raw['is_marketplace_order'] }
      unflagged = masked.merge('id' => 41_000_199, 'is_marketplace_order' => nil,
                               'customer' => masked['customer'].merge('id' => 90_078, 'mobile' => '9665***2233', 'email' => 's***@example.com'))
      stub_request(:get, orders_url).with(query: hash_including({})).to_return(respond([masked, unflagged]))

      expect(provider.find_customers(phone: '+966551112233')).to eq([])
      expect(provider.find_customers(email: 's***@example.com')).to eq([])
      expect(provider.send(:normalizer).customer(unflagged['customer'])).to have_attributes(emails: [], phones: [])
    end

    it 'does not search with a phone number it cannot parse' do
      expect(provider.find_customers(phone: '12')).to eq([])
      expect(a_request(:get, orders_url)).not_to have_been_made
    end
  end

  describe '#list_customer_orders' do
    let!(:list) do
      stub_request(:get, orders_url).with(query: { 'customer_id' => '90001', 'per_page' => '50', 'sort_by' => 'desc', 'payload_type' => 'default' })
                                    .to_return(respond(orders['orders']))
    end

    it "returns only the linked customer's orders, newest first, even if the filter were ignored" do
      result = provider.list_customer_orders('90001', limit: 5)

      expect(result.map(&:external_order_id)).to eq(%w[41000102 41000101 41000103])
      expect(list).to have_been_requested.once
    end

    it 'normalizes an order in delivery with its courier and tracking' do
      order = provider.list_customer_orders('90001', limit: 1).first

      expect(order.to_h).to include(
        provider: 'zid', external_order_id: '41000102', order_number: '41000102', status: 'shipped', provider_status: 'indelivery',
        payment_status: 'paid', currency: 'SAR', customer: { external_id: '90001', name: 'Sara Ali' },
        tracking: { number: 'KWB123456789SA', url: 'https://track.kwickbox.example/KWB123456789SA' },
        admin_order_url: nil, customer_order_url: nil, created_at: '2026-09-29T07:15:00Z', updated_at: '2026-09-30T06:00:00Z'
      )
      expect(order.shipments).to eq([{ provider: 'kwickbox', status: 'in_transit', provider_status: 'in_transit', type: 'shipment',
                                       tracking_number: 'KWB123456789SA', tracking_url: 'https://track.kwickbox.example/KWB123456789SA' }])
      expect(order.shipping).to eq(method: 'Testing service level', total: nil, provider: 'kwickbox', status: 'in_transit')
      product = orders['orders'].first['products'].first
      expect(order.items.first).to eq(name: product['name'], quantity: 1, total: BigDecimal(product['total'].to_s).to_s('F'))
      expect(order.item_count).to eq(order.items.sum { |item| item[:quantity] })
    end

    it 'maps statuses explicitly and payment only from what Zid states' do
      by_id = provider.list_customer_orders('90001', limit: 5).index_by(&:external_order_id)

      expect(by_id['41000101'].to_h.slice(:status, :provider_status, :payment_status)).to eq(status: 'processing', provider_status: 'new',
                                                                                             payment_status: 'unpaid')
      expect(by_id['41000103'].to_h.slice(:status, :provider_status, :payment_status)).to eq(status: 'other', provider_status: 'reversed',
                                                                                             payment_status: 'unknown')
      expect(by_id['41000101'].shipments).to eq([])
      expect(by_id['41000101'].tracking).to be_nil
    end

    it 'maps every documented order status and payment status, and unknown ones to other and unknown' do
      normalizer = Commerce::Providers::Zid::Normalizer.new(time_zone: 'Asia/Riyadh')
      raw = orders['orders'].first
      statuses = %w[new preparing ready inDelivery indelivery delivered cancelled canceled reverse_in_progress].index_with do |code|
        normalizer.order(raw.merge('order_status' => { 'code' => code })).status
      end
      payments = %w[paid pending refunded voided partially_paid].index_with do |value|
        normalizer.order(raw.merge('payment_status' => value)).payment_status
      end

      expect(statuses).to eq('new' => 'processing', 'preparing' => 'processing', 'ready' => 'processing', 'inDelivery' => 'shipped',
                             'indelivery' => 'shipped', 'delivered' => 'delivered', 'cancelled' => 'cancelled', 'canceled' => 'cancelled',
                             'reverse_in_progress' => 'other')
      expect(payments).to eq('paid' => 'paid', 'pending' => 'unpaid', 'refunded' => 'refunded', 'voided' => 'unknown', 'partially_paid' => 'unknown')
      expect(normalizer.order(raw.merge('order_status' => { 'code' => 'delivered' }, 'payment_status' => 'pending')).payment_status).to eq('unpaid')
    end

    it 'keeps tracking links only when https, and the item count unknown without products' do
      raw = orders['orders'].first
      raw['shipping']['method']['tracking']['url'] = 'http://track.example/KWB1'
      normalizer = Commerce::Providers::Zid::Normalizer.new

      order = normalizer.order(raw.except('products'))

      expect(order.tracking).to eq(number: 'KWB123456789SA', url: nil)
      expect(order.to_h.slice(:items, :item_count)).to eq(items: [], item_count: nil)
    end

    it 'refuses malformed orders' do
      stub_request(:get, orders_url).with(query: hash_including({})).to_return(respond([{ 'id' => 'x', 'customer' => { 'id' => 90_001 } }]))

      expect(error_for { provider.list_customer_orders('90001', limit: 5) }).to eq(code: 'INVALID_RESPONSE', reason: 'malformed_order')
    end
  end

  describe 'tokens and errors' do
    it 'refreshes expiring tokens before reading' do
      store.update!(credentials: store.credentials.merge('expires_at' => 10.days.from_now.utc.iso8601))
      stub_request(:post, 'https://oauth.zid.sa/oauth/token')
        .to_return(status: 200, body: { access_token: 'manager-2', authorization: 'auth-2', refresh_token: 'refresh-2',
                                        expires_in: 31_536_000 }.to_json)
      read = stub_request(:get, orders_url).with(query: hash_including({}), headers: { 'X-Manager-Token' => 'manager-2' })
                                           .to_return(respond([]))

      provider.find_customers(email: 'sara.ali@example.com')

      expect(read).to have_been_requested.once
    end

    it 'refreshes once and retries once when Zid rejects the tokens, including with a redirect to its login page' do
      stub_request(:post, 'https://oauth.zid.sa/oauth/token')
        .to_return(status: 200, body: { access_token: 'manager-2', authorization: 'auth-2', refresh_token: 'refresh-2',
                                        expires_in: 31_536_000 }.to_json)
      stub_request(:get, orders_url).with(query: hash_including({}), headers: { 'X-Manager-Token' => 'zid-manager-factory' })
                                    .to_return(status: 302, headers: { 'Location' => 'https://web.zid.sa/login' })
      stub_request(:get, orders_url).with(query: hash_including({}), headers: { 'X-Manager-Token' => 'manager-2' }).to_return(respond([]))

      expect(provider.find_customers(email: 'sara.ali@example.com')).to eq([])
      expect(store.reload.credentials['access_token']).to eq('manager-2')
    end

    it 'moves the store to needs_reauth when the renewed tokens are rejected too' do
      stub_request(:post, 'https://oauth.zid.sa/oauth/token')
        .to_return(status: 200, body: { access_token: 'manager-2', authorization: 'auth-2', refresh_token: 'refresh-2',
                                        expires_in: 31_536_000 }.to_json)
      stub_request(:get, orders_url).with(query: hash_including({})).to_return(status: 401, body: '{"status":401,"success":false}')

      expect(error_for { provider.find_customers(email: 'sara.ali@example.com') }).to eq(code: 'AUTH_INVALID', reason: 'tokens_rejected')
      expect(store.reload).to be_needs_reauth
    end

    it 'stops calling a store that Zid rate limited until Zid says to retry' do
      stub_request(:get, orders_url).with(query: hash_including({})).to_return(status: 429, headers: { 'Retry-After' => '30' })

      expect(error_for { provider.find_customers(email: 'sara.ali@example.com') }).to eq(code: 'RATE_LIMITED')
      expect(error_for { described_class.new(store, credentials: nil).find_customers(email: 'sara.ali@example.com') }).to eq(code: 'RATE_LIMITED')
      expect(a_request(:get, orders_url).with(query: hash_including({}))).to have_been_made.once
    end

    it 'checks that the tokens belong to this store' do
      stub_request(:get, 'https://api.zid.sa/v1/managers/account/profile').to_return(status: 200,
                                                                                     body: file_fixture('commerce/zid/profile.json').read)

      expect(provider.health).to be(true)
      expect(error_for { described_class.new(create(:commerce_store, :zid, external_store_id: '42'), credentials: nil).health })
        .to eq(code: 'AUTH_INVALID')
    end
  end
end
