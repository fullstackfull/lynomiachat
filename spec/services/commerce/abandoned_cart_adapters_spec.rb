require 'rails_helper'

# Abandoned cart adapters (docs/commerce/30-abandoned-carts.md §providers) against documented shapes: Salla's Cart
# resource (@salla.sa types) and Shopify's AbandonedCheckout (Admin GraphQL 2026-07). Zid's is in abandoned_carts_spec.
RSpec.describe Commerce::AbandonedCart do
  include_context 'with commerce encryption'

  describe Commerce::Providers::Salla do
    include_context 'with salla app'

    let(:store) { create(:commerce_store, :salla, external_store_id: '1234509876', base_url: 'https://salla.sa/lynomia-demo') }
    let(:raw) do
      { id: 551_100, checkout_url: 'https://salla.sa/lynomia-demo/checkout/abc', age_in_minutes: 95, coupon: nil,
        total: { amount: 230, currency: 'SAR' }, subtotal: { amount: 230, currency: 'SAR' }, total_discount: { amount: 0, currency: 'SAR' },
        created_at: { date: '2026-09-30 10:00:00.000000', timezone_type: 3, timezone: 'Asia/Riyadh' },
        updated_at: { date: '2026-09-30 10:30:00.000000', timezone_type: 3, timezone: 'Asia/Riyadh' },
        customer: { id: 1_227_534_533, name: 'Omar', mobile: '+966551112233', email: 'Omar@Example.com', city: 'Riyadh' },
        items: [{ id: 1, product_id: 77, quantity: 2 }] }
    end

    before do
      body = { status: 200, success: true, data: [raw] }
      stub_request(:get, 'https://api.salla.dev/admin/v2/carts/abandoned').with(query: { per_page: 30 }).to_return(status: 200, body: body.to_json)
    end

    it 'reads the latest page of abandoned carts as the provider-neutral cart' do
      cart = Commerce::Providers.for(store).abandoned_carts.sole

      expect(cart.to_h).to include(provider: 'salla', external_cart_id: '551100', currency: 'SAR', total: '230.0', status: 'abandoned',
                                   created_at: '2026-09-30T07:00:00Z', items: [{ name: nil, quantity: 2 }], customer_reference: '1227534533',
                                   email: 'omar@example.com', phone: '+966551112233', recovery_url: 'https://salla.sa/lynomia-demo/checkout/abc')
      expect(Commerce::Providers.for(store).recovery_hosts).to include('salla.sa', '.salla.sa')
    end

    it 'needs carts.read when the token lists its scopes, and finds no cart Salla no longer lists' do
      expect(Commerce::Providers.for(store).cart_access_problem).to eq('missing_scope')

      store.update!(credentials: store.credentials.merge('scope' => 'offline_access orders.read customers.read carts.read'))
      expect(Commerce::Providers.for(store).cart_access_problem).to be_nil
      expect { Commerce::Providers.for(store).abandoned_cart('9') }.to raise_error(Commerce::Error, 'NOT_FOUND')
    end
  end

  describe Commerce::Providers::Shopify do
    include_context 'with shopify commerce app'

    let(:store) { create(:commerce_store, :shopify, external_store_id: '68210001', base_url: 'https://lynomia-demo.myshopify.com') }
    let(:graphql) { 'https://lynomia-demo.myshopify.com/admin/api/2026-07/graphql.json' }
    let(:checkout) do
      { id: 'gid://shopify/AbandonedCheckout/9101', name: '#9101', abandonedCheckoutUrl: 'https://lynomia-demo.myshopify.com/9101/checkouts/ac/recover?key=k',
        createdAt: '2026-09-30T08:00:00Z', updatedAt: '2026-09-30T08:20:00Z', completedAt: nil, lineItemsQuantity: 3,
        customer: { id: 'gid://shopify/Customer/7001' }, totalPriceSet: { presentmentMoney: { amount: '410.0', currencyCode: 'SAR' } },
        lineItems: { nodes: [{ title: 'Oud Perfume 50ml', quantity: 2 }, { title: 'Gift Box', quantity: 1 }] } }
    end
    let(:sent) { [] }

    before do
      stub_request(:post, graphql).to_return do |request|
        sent << JSON.parse(request.body)
        { status: 200, body: { data: { abandonedCheckouts: { nodes: [checkout] } } }.to_json }
      end
    end

    it 'reads open checkouts with the customer\'s id only, never contact details or addresses' do
      cart = Commerce::Providers.for(store).abandoned_carts.sole

      expect(cart.to_h).to include(external_cart_id: '9101', customer_reference: '7001', email: nil, phone: nil, status: 'abandoned',
                                   items: [{ name: 'Oud Perfume 50ml', quantity: 2 }, { name: 'Gift Box', quantity: 1 }], total: '410.0')
      expect(sent.first['variables']).to eq('first' => 20, 'query' => 'status:open')
      expect(sent.first['query']).not_to include('email', 'phone', 'Address', 'billing', 'shipping')
    end

    it 'sees a recovered checkout as recovered, and refuses a protected-data denial' do
      checkout[:completedAt] = '2026-09-30T09:00:00Z'
      expect(Commerce::Providers.for(store).abandoned_cart('9101')).to have_attributes(status: 'recovered')
      expect(sent.last['variables']).to eq('first' => 1, 'query' => 'id:9101')

      stub_request(:post, graphql).to_return(status: 200, body: { errors: [{ message: 'This app is not approved to access the Customer object.',
                                                                             extensions: { code: 'ACCESS_DENIED' } }] }.to_json)
      expect { Commerce::Providers.for(store).abandoned_carts }.to raise_error(Commerce::Error, 'PROTECTED_DATA_NOT_APPROVED')
    end
  end
end
