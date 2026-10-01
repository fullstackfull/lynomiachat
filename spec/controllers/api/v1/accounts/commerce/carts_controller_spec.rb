require 'rails_helper'

# The administrators' recovery queue (docs/commerce/31-sales-recovery.md §queue): bounded, filtered, no contact details.
RSpec.describe 'Commerce recovery queue API', type: :request do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:store) { create(:commerce_store, :zid, account: account, external_store_id: '318001', metadata: { 'time_zone' => 'Asia/Riyadh' }) }
  let(:contact) { create(:contact, account: account, name: 'Omar Khalil') }
  let(:path) { "/api/v1/accounts/#{account.id}/commerce/carts" }
  let(:carts) do
    at = ->(time) { time.in_time_zone('Asia/Riyadh').strftime('%F %T') }
    [{ id: 'c0ffee01-0000-4000-8000-000000000000', url: 'https://my-store.zid.store/r/1', phase: 'new', customer_id: 90_001,
       customer_mobile: '966551112233', customer_email: 'omar@example.com', cart_total: 99, currency_code: 'SAR', products_count: 1,
       created_at: at.call(3.days.ago), updated_at: at.call(3.days.ago) },
     { id: 'c0ffee02-0000-4000-8000-000000000000', url: 'https://my-store.zid.store/r/2', phase: 'new', customer_id: 90_002, cart_total: 50,
       currency_code: 'SAR', products_count: 2, created_at: at.call(2.hours.ago), updated_at: at.call(2.hours.ago) },
     { id: 'c0ffee03-0000-4000-8000-000000000000', url: 'https://my-store.zid.store/r/3', phase: 'completed', customer_id: 90_003,
       cart_total: 70, currency_code: 'SAR', products_count: 1, created_at: at.call(1.hour.ago), updated_at: at.call(1.hour.ago) }]
  end

  around { |example| with_modified_env(COMMERCE_ALLOW_PRE_UAT_PROVIDERS: 'true') { example.run } }

  before do
    account.enable_features!('lynomia_commerce')
    InstallationConfig.where(name: 'ZID_RECOVERY_ENABLED').first_or_initialize.update!(value: true, locked: false)
    GlobalConfig.clear_cache
    Redis::Alfred.scan_each(match: 'COMMERCE::V1::*') { |key| Redis::Alfred.delete(key) }
    create(:commerce_customer_link, store: store, account: account, contact: contact, external_customer_id: '90001', match_source: :manual)
    stub_request(:get, %r{/abandoned-carts\?}).to_return(status: 200, body: { 'abandoned-carts' => carts }.to_json)
  end

  it 'lists abandoned carts, linked contacts first, with no contact details or recovery links' do
    get path, headers: admin.create_new_auth_token, params: { status: 'abandoned' }

    rows = response.parsed_body['payload']
    expect(rows.pluck('external_cart_id')).to eq(%w[c0ffee01-0000-4000-8000-000000000000 c0ffee02-0000-4000-8000-000000000000])
    expect(rows.first).to include('contact' => { 'id' => contact.id, 'name' => 'Omar Khalil' }, 'items_count' => 1, 'total' => '99.0')
    expect(rows.second['contact']).to be_nil
    expect(response.body).not_to include('966551112233', 'omar@example.com', 'my-store.zid.store', '90001')
  end

  it 'filters by age, status and linked contact' do
    get path, headers: admin.create_new_auth_token, params: { age: '24h' }
    expect(response.parsed_body['payload'].pluck('status')).to eq(%w[recovered abandoned])

    get path, headers: admin.create_new_auth_token, params: { linked: 'false', status: 'recovered' }
    expect(response.parsed_body['payload'].pluck('external_cart_id')).to eq(%w[c0ffee03-0000-4000-8000-000000000000])
  end

  it 'is for administrators only' do
    get path, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
    expect(a_request(:get, /abandoned-carts/)).not_to have_been_made
  end
end
