require 'rails_helper'

# The conversation's abandoned carts endpoint (docs/commerce/30-abandoned-carts.md): only the account's own stores that
# offer carts, only the conversation contact's carts, only to who can see the conversation.
RSpec.describe 'Commerce abandoned carts API', type: :request do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp.inbox, contact: contact,
                          contact_inbox: create(:contact_inbox, contact: contact, inbox: whatsapp.inbox, source_id: '966551112233'))
  end
  let!(:zid) { create(:commerce_store, :zid, account: account, external_store_id: '318001', metadata: { 'time_zone' => 'Asia/Riyadh' }) }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/carts" }
  let(:carts) do
    [{ id: 'c0ffee01-0000-4000-8000-000000000000', url: 'https://my-store.zid.store/r/1', phase: 'new', customer_mobile: '966551112233',
       cart_total: 99, currency_code: 'SAR', products_count: 1, created_at: 1.hour.ago.in_time_zone('Asia/Riyadh').strftime('%F %T') },
     { id: 'c0ffee02-0000-4000-8000-000000000000', url: 'https://my-store.zid.store/r/2', phase: 'new', customer_mobile: '966500000001',
       cart_total: 50, currency_code: 'SAR', products_count: 1, created_at: 1.hour.ago.in_time_zone('Asia/Riyadh').strftime('%F %T') }]
  end

  around { |example| with_modified_env(COMMERCE_ALLOW_PRE_UAT_PROVIDERS: 'true') { example.run } }

  before do
    account.enable_features!('lynomia_commerce')
    create(:inbox_member, user: agent, inbox: whatsapp.inbox)
    InstallationConfig.where(name: 'ZID_RECOVERY_ENABLED').first_or_initialize.update!(value: true, locked: false)
    GlobalConfig.clear_cache
    Redis::Alfred.scan_each(match: 'COMMERCE::V1::*') { |key| Redis::Alfred.delete(key) }
    stub_request(:get, %r{/abandoned-carts\?}).to_return(status: 200, body: { 'abandoned-carts' => carts }.to_json)
  end

  it 'answers the contact\'s carts only, store by store' do
    get path, headers: agent.create_new_auth_token, as: :json

    store = response.parsed_body['stores'].sole
    expect(store).to include('state' => 'ok', 'store' => { 'id' => zid.id, 'name' => zid.name, 'provider' => 'zid' })
    expect(store['carts'].pluck('external_cart_id')).to eq(['c0ffee01-0000-4000-8000-000000000000'])
    expect(response.body).not_to include('966500000001', 'my-store.zid.store/r/')
  end

  it 'flags in the stores list which stores offer carts' do
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores", headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['payload'].sole).to include('id' => zid.id, 'carts' => true)
  end

  it 'reaches no other account\'s store, and no store that does not offer carts' do
    other = create(:commerce_store, :zid, external_store_id: '318999')
    get path, params: { store_id: other.id }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)

    woo = create(:commerce_store, account: account)
    get path, params: { store_id: woo.id }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'answers nothing to another account or to an agent who cannot see the conversation' do
    get path, headers: create(:user, account: create(:account), role: :administrator).create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    get path, headers: create(:user, account: account, role: :agent).create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(a_request(:get, %r{/abandoned-carts})).not_to have_been_made
  end
end
