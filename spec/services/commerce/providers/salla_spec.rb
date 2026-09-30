require 'rails_helper'

# Responses follow Salla's documented shapes (spec/fixtures/files/commerce/salla; docs/commerce/13-salla-e2e.md explains
# why no live store could be recorded).
RSpec.describe Commerce::Providers::Salla do
  include_context 'with commerce encryption'
  include_context 'with salla app'

  let(:api) { 'https://api.salla.dev/admin/v2' }
  let(:store) { create(:commerce_store, :salla, external_store_id: '1234509876') }
  let(:provider) { described_class.new(store, credentials: store.credentials) }
  let(:customers) { JSON.parse(file_fixture('commerce/salla/customers.json').read) }
  let(:orders) { JSON.parse(file_fixture('commerce/salla/orders.json').read) }
  let(:shipments) { JSON.parse(file_fixture('commerce/salla/shipments.json').read) }

  def respond(data)
    { status: 200, body: { status: 200, success: true, data: data }.to_json }
  end

  def stub_orders(data = orders['data'])
    stub_request(:get, "#{api}/orders").with(query: { 'customer_id' => '1227534533', 'per_page' => '60' }).to_return(respond(data))
  end

  def stub_shipments(order_id, data = [])
    stub_request(:get, "#{api}/shipments").with(query: { 'order_id' => order_id.to_s }).to_return(respond(data))
  end

  def error_for
    yield
    nil
  rescue Commerce::Error => e
    e.as_json
  end

  describe '#find_customers' do
    it 'searches by the national number and keeps only an exact E.164 mobile match' do
      search = stub_request(:get, "#{api}/customers").with(query: { 'keyword' => '551112233', 'per_page' => '20' })
                                                     .with(headers: { 'Authorization' => 'Bearer salla-access-factory' })
                                                     .to_return(status: 200, body: customers.to_json)

      found = provider.find_customers(phone: '+966551112233')

      expect(found.map(&:to_h)).to eq([{ external_id: '1227534533', name: 'Omar Khalil', emails: ['omar.khalil@example.com'],
                                         phones: ['+966551112233'], registered: true }])
      expect(search).to have_been_requested.once
    end

    it 'matches an email exactly and case-insensitively' do
      stub_request(:get, "#{api}/customers").with(query: hash_including('keyword' => 'omar.khalil@example.com'))
                                            .to_return(status: 200, body: customers.to_json)

      expect(provider.find_customers(email: ' Omar.Khalil@example.COM ').map(&:external_id)).to eq(['1227534533'])
    end

    it 'never matches by name' do
      stub_request(:get, "#{api}/customers").with(query: hash_including('keyword' => 'nobody@example.com'))
                                            .to_return(status: 200, body: customers.to_json)

      expect(provider.find_customers(email: 'nobody@example.com')).to eq([])
    end

    it 'returns every exact match so an agent chooses' do
      twin = customers['data'].first.merge('id' => 1_227_534_600, 'email' => 'second@example.com')
      stub_request(:get, "#{api}/customers").with(query: hash_including('keyword' => '551112233')).to_return(respond([customers['data'].first, twin]))

      expect(provider.find_customers(phone: '+966551112233').map(&:external_id)).to eq(%w[1227534533 1227534600])
    end

    it 'does not search with a phone number it cannot parse' do
      expect(provider.find_customers(phone: '+1')).to eq([])
      expect(a_request(:any, /salla/)).not_to have_been_made
    end
  end

  describe '#list_customer_orders' do
    before do
      stub_orders
      orders['data'].each { |order| stub_shipments(order['id']) }
      stub_shipments(1_861_092_002, shipments['data'])
    end

    it 'reads one page of the customer\'s orders and returns the latest, newest first' do
      result = provider.list_customer_orders('1227534533', limit: 5)

      expect(result.map(&:order_number)).to eq(%w[30013 30012 30011 30015 30014])
      expect(a_request(:get, "#{api}/orders").with(query: hash_including('customer_id' => '1227534533'))).to have_been_made.once
      expect(a_request(:get, /expanded/)).not_to have_been_made
    end

    it 'fetches shipments only for the orders it shows' do
      provider.list_customer_orders('1227534533', limit: 5)

      expect(a_request(:get, "#{api}/shipments").with(query: { 'order_id' => '1861092006' })).not_to have_been_made
      expect(a_request(:get, "#{api}/shipments").with(query: { 'order_id' => '1861092002' })).to have_been_made.once
    end

    it 'normalizes a shipped order with several shipments' do
      order = provider.list_customer_orders('1227534533', limit: 5).find { |o| o.order_number == '30012' }

      expect(order.to_h.except(:shipments)).to eq(
        provider: 'salla', external_order_id: '1861092002', order_number: '30012', status: 'shipped', provider_status: 'shipped',
        payment_status: 'unknown', currency: 'SAR', total: '245', created_at: '2026-09-10T15:40:00Z', updated_at: nil,
        items: [{ name: 'Rose Cream', quantity: 2, total: '150' }, { name: 'Lip Balm', quantity: 3, total: '75' }], item_count: 5,
        customer: { external_id: '1227534533', name: 'Omar Khalil' },
        shipping: { method: 'Aramex, SMSA', total: nil, provider: 'Aramex', status: 'in_transit' },
        tracking: { number: 'AX123456789SA', url: 'https://www.aramex.com/track/results?ShipmentNumber=AX123456789SA' },
        admin_order_url: 'https://s.salla.sa/orders/order/Wq1861092002Zx', customer_order_url: nil
      )
      expect(order.shipments.map { |shipment| shipment.values_at(:provider, :status, :tracking_number) })
        .to eq([%w[Aramex in_transit AX123456789SA], %w[SMSA out_for_delivery SM000111]])
    end

    it 'says unpaid only when Salla says payment is pending, and never infers paid' do
      result = provider.list_customer_orders('1227534533', limit: 5).to_h { |order| [order.provider_status, order.payment_status] }

      expect(result).to eq('payment_pending' => 'unpaid', 'shipped' => 'unknown', 'completed' => 'unknown', 'under_review' => 'unknown',
                           'canceled' => 'unknown')
    end

    it 'maps a custom status by the status it is based on, and unknown statuses to other' do
      data = orders['data'].first(1).map { |order| order.merge('status' => { 'slug' => 'restoring', 'name' => 'قيد الاسترجاع' }) }
      stub_orders(data + orders['data'][4, 1])

      result = provider.list_customer_orders('1227534533', limit: 5).to_h { |order| [order.order_number, order.status] }

      expect(result).to eq('30011' => 'other', '30015' => 'on_hold')
    end

    it 'keeps tracking only for trackable https links, and never tracks a return' do
      stub_shipments(1_861_092_002, [
                       shipments['data'][0].merge('trackable' => false),
                       shipments['data'][1].merge('tracking_link' => 'http://track.example.com/1', 'tracking_number' => nil),
                       shipments['data'][0].merge('type' => 'return', 'tracking_number' => 'RET-1')
                     ])

      order = provider.list_customer_orders('1227534533', limit: 5).find { |o| o.order_number == '30012' }

      expect(order.tracking).to eq(number: 'AX123456789SA', url: nil)
      expect(order.shipments.first(2).pluck(:tracking_url)).to eq([nil, nil])
      expect(order.shipments.last).to include(type: 'return', tracking_number: 'RET-1')
    end

    it 'drops an admin link that is not Salla\'s dashboard' do
      stub_orders([orders['data'][0].merge('urls' => { 'admin' => 'https://evil.example.com/orders/1' })])

      expect(provider.list_customer_orders('1227534533', limit: 5).sole.admin_order_url).to be_nil
    end

    it 'leaves the item count unknown when the order comes without items' do
      stub_orders([orders['data'][0].except('items')])

      expect(provider.list_customer_orders('1227534533', limit: 5).sole).to have_attributes(items: [], item_count: nil)
    end

    it 'refuses malformed orders' do
      stub_orders([orders['data'][0].except('amounts')])

      expect(error_for { provider.list_customer_orders('1227534533', limit: 5) }).to eq(code: 'INVALID_RESPONSE', reason: 'malformed_order')
    end
  end

  describe 'tokens and errors' do
    it 'refreshes an expiring token before reading, with the same single-use rules' do
      store.update!(credentials: store.credentials.merge('access_token_expires_at' => 1.hour.from_now.utc.iso8601))
      stub_request(:post, 'https://accounts.salla.sa/oauth2/token')
        .to_return(status: 200, body: { access_token: 'access-new', refresh_token: 'refresh-new', token_type: 'bearer',
                                        expires: 14.days.from_now.to_i, scope: 'offline_access customers.read orders.read shipping.read' }.to_json)
      search = stub_request(:get, "#{api}/customers").with(query: hash_including({}), headers: { 'Authorization' => 'Bearer access-new' })
                                                     .to_return(respond([]))

      provider.find_customers(email: 'omar.khalil@example.com')

      expect(search).to have_been_requested.once
    end

    it 'reports a rejected token as AUTH_INVALID' do
      rejected = { status: 401, success: false, error: { code: 'Unauthorized', message: 'The access token is invalid' } }
      stub_request(:get, "#{api}/customers").with(query: hash_including({})).to_return(status: 401, body: rejected.to_json)

      expect(error_for { provider.find_customers(email: 'omar.khalil@example.com') }).to eq(code: 'AUTH_INVALID')
    end

    it 'stops calling a store that is rate limited until Salla says to retry' do
      limited = stub_request(:get, "#{api}/customers").with(query: hash_including({}))
                                                      .to_return(status: 429, headers: { 'Retry-After' => '30', 'X-RateLimit-Remaining' => '0' })

      expect(error_for { provider.find_customers(email: 'omar.khalil@example.com') }).to eq(code: 'RATE_LIMITED')
      expect(error_for { described_class.new(store, credentials: nil).find_customers(email: 'omar.khalil@example.com') }).to eq(code: 'RATE_LIMITED')
      expect(limited).to have_been_requested.once
      expect(Redis::Alfred.ttl('COMMERCE::SALLA::MERCHANT::1234509876::BACKOFF')).to be_between(1, 30)
    end

    it 'backs off when Salla reports no requests left, until its reset time' do
      stub_request(:get, "#{api}/customers").with(query: hash_including({}))
                                            .to_return(respond([]).merge(headers: { 'X-RateLimit-Remaining' => '0',
                                                                                    'X-RateLimit-Reset' => (Time.now.to_i + 20).to_s }))

      provider.find_customers(email: 'omar.khalil@example.com')

      expect(error_for { described_class.new(store, credentials: nil).find_customers(email: 'x@example.com') }).to eq(code: 'RATE_LIMITED')
      expect(Redis::Alfred.ttl('COMMERCE::SALLA::MERCHANT::1234509876::BACKOFF')).to be_between(15, 20)
    end

    it 'checks that the token belongs to this store' do
      user_info = file_fixture('commerce/salla/user_info.json').read
      stub_request(:get, 'https://accounts.salla.sa/oauth2/user/info').to_return(status: 200, body: user_info)

      expect(provider.health).to be(true)
      expect(error_for { described_class.new(build(:commerce_store, :salla, external_store_id: '42'), credentials: nil).health })
        .to eq(code: 'AUTH_INVALID')
    end
  end
end
