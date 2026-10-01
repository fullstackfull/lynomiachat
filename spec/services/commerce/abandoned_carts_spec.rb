require 'rails_helper'

# Which abandoned carts are the conversation's contact's (docs/commerce/30-abandoned-carts.md §matching), against Zid's
# documented abandoned carts API (Commerce::Providers::Zid::Carts).
RSpec.describe Commerce::AbandonedCarts do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, :zid, account: account, external_store_id: '318001', metadata: { 'time_zone' => 'Asia/Riyadh' }) }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:contact) { create(:contact, account: account, name: 'Omar Khalil', email: 'omar@example.com', phone_number: '+966551112299') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: whatsapp.inbox, source_id: '966551112233') }
  let(:conversation) { create(:conversation, account: account, inbox: whatsapp.inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:api) { 'https://api.zid.sa/v1/managers/store/abandoned-carts' }
  let(:cart) do
    lambda do |id, **fields|
      { id: "c0ffee#{id}-0000-4000-8000-000000000000", url: "https://my-store.zid.store/cart/recover/#{id}", cart_id: "cart-#{id}", order_id: nil,
        phase: 'payment_method', customer_id: nil, customer_name: 'Omar Khalil', customer_email: nil, customer_mobile: nil, products_count: 2,
        reminders_count: 0, cart_total: 120.5, cart_total_string: '120.50 SAR', currency_code: 'SAR',
        created_at: 2.hours.ago.in_time_zone('Asia/Riyadh').strftime('%F %T'), updated_at: 1.hour.ago.in_time_zone('Asia/Riyadh').strftime('%F %T') }
        .merge(fields)
    end
  end
  let(:answer) do
    lambda do |carts|
      stub_request(:get, api).with(query: hash_including('page' => '1')).to_return(status: 200, body: { 'abandoned-carts' => carts }.to_json)
    end
  end
  let(:list) { -> { described_class.new(store: store, conversation: conversation).list(force: true) } }

  around { |example| with_modified_env(COMMERCE_ALLOW_PRE_UAT_PROVIDERS: 'true') { example.run } }

  before do
    InstallationConfig.where(name: 'ZID_RECOVERY_ENABLED').first_or_initialize.update!(value: true, locked: false)
    GlobalConfig.clear_cache
    Redis::Alfred.scan_each(match: 'COMMERCE::V1::*') { |key| Redis::Alfred.delete(key) }
  end

  it 'shows the carts of the verified phone, without contact details or links, and never by name or editable fields' do
    answer.call([cart.call(1, customer_mobile: '966551112233'), cart.call(2, customer_mobile: '966551112299'),
                 cart.call(3, customer_email: 'omar@example.com'), cart.call(4)])

    result = list.call

    expect(result[:state]).to eq('ok')
    expect(result[:carts].pluck('external_cart_id', 'match')).to eq([[cart.call(1)[:id], 'verified_phone']])
    expect(result[:carts].first.keys).not_to include('email', 'phone', 'recovery_url', 'customer_reference')
    expect(result.to_json).not_to include('966551112233', 'recover/1', 'Omar')
  end

  it 'asks Zid for the linked customer\'s carts and never shows another customer\'s, even with the same phone' do
    create(:commerce_customer_link, store: store, account: account, contact: contact, external_customer_id: '90001', match_source: :verified_phone)
    carts = [cart.call(1, customer_id: 90_001), cart.call(2, customer_id: 90_002, customer_mobile: '966551112233')]
    filtered = stub_request(:get, api).with(query: hash_including('customer_id' => '90001'))
                                      .to_return(status: 200, body: { 'abandoned-carts' => carts }.to_json)

    expect(list.call[:carts].pluck('match')).to eq(['linked_customer'])
    expect(filtered).to have_been_requested.once
  end

  it 'never matches a masked identity, the customer an agent unlinked, or a phone several customers share' do
    create(:commerce_customer_link, store: store, account: account, contact: contact, external_customer_id: '90002', match_source: :suppressed)
    answer.call([cart.call(1, customer_mobile: '*******2233'), cart.call(2, customer_id: 90_002, customer_mobile: '966551112233')])
    expect(list.call[:carts]).to eq([])

    answer.call([cart.call(3, customer_id: 90_003, customer_mobile: '966551112233'),
                 cart.call(4, customer_id: 90_004, customer_mobile: '966551112233')])
    expect(list.call[:carts]).to eq([])
  end

  it 'offers neither recovered nor expired carts' do
    old = 40.days.ago.in_time_zone('Asia/Riyadh').strftime('%F %T')
    answer.call([cart.call(1, customer_mobile: '966551112233', phase: 'completed'), cart.call(2, customer_mobile: '966551112233', order_id: 77),
                 cart.call(3, customer_mobile: '966551112233', created_at: old)])

    expect(list.call[:carts]).to eq([])
  end

  it 'matches an email conversation by the address it came from only' do
    email_inbox = create(:channel_email, account: account).inbox
    email_identity = create(:contact_inbox, contact: contact, inbox: email_inbox, source_id: 'Omar@Example.com')
    email_conversation = create(:conversation, account: account, inbox: email_inbox, contact: contact, contact_inbox: email_identity)
    answer.call([cart.call(1, customer_email: 'omar@example.com'), cart.call(2, customer_email: 'o***@example.com')])

    result = described_class.new(store: store, conversation: email_conversation).list(force: true)

    expect(result[:carts].pluck('match')).to eq(['verified_email'])
  end

  it 'reads nothing while the installation keeps the provider\'s carts off' do
    InstallationConfig.find_by!(name: 'ZID_RECOVERY_ENABLED').update!(value: false)
    GlobalConfig.clear_cache

    expect(list.call).to include(state: 'unavailable', error: 'RECOVERY_DISABLED', carts: [])
    expect(a_request(:get, /abandoned-carts/)).not_to have_been_made
  end

  it 'has no abandoned carts for WooCommerce, whose core has none' do
    woo = create(:commerce_store, account: account)

    expect(described_class.offered?(woo)).to be(false)
    expect(described_class.new(store: woo, conversation: conversation).list).to include(error: 'RECOVERY_DISABLED')
  end

  it 'gives a fresh cart only while it is still the contact\'s, and a forged id nothing' do
    detail = cart.call(1, customer_mobile: '966551112233', products: [{ name: 'Oud', quantity: 2 }])
    stub_request(:get, "#{api}/#{detail[:id]}").to_return(status: 200, body: { abandoned_cart: detail }.to_json)
    fresh, match = described_class.new(store: store, conversation: conversation).fresh(detail[:id])
    expect([fresh.recovery_url, fresh.items, match])
      .to eq(['https://my-store.zid.store/cart/recover/1', [{ name: 'Oud', quantity: 2 }], 'verified_phone'])

    other = cart.call(2, customer_mobile: '966500000000')
    stub_request(:get, "#{api}/#{other[:id]}").to_return(status: 200, body: { abandoned_cart: other }.to_json)
    expect { described_class.new(store: store, conversation: conversation).fresh(other[:id]) }.to raise_error(Commerce::Error, 'NOT_FOUND')
    expect { described_class.new(store: store, conversation: conversation).fresh('../orders') }.to raise_error(Commerce::Error, 'NOT_FOUND')
  end
end
