require 'rails_helper'

# Audiences through the APIs Chatwoot already has (docs/audience/02, 04): the contact filter, saved contact segments
# (custom_filters) and the Commerce field options.
RSpec.describe 'Audiences API', type: :request do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:store) { create(:commerce_store, account: account, name: 'Syria Cosmetics') }
  let(:buyer) { create(:contact, account: account, email: 'buyer@example.com') }
  let(:unread) { create(:contact, account: account, email: 'unread@example.com') }
  let(:other_account) { create(:account) }
  let(:other_admin) { create(:user, account: other_account, role: :administrator) }
  let(:big_spenders) do
    { payload: [{ attribute_key: 'commerce_spend_sar', filter_operator: 'is_greater_than', values: ['1000'] }] }
  end

  before do
    account.enable_features!('lynomia_commerce')
    link = create(:commerce_customer_link, store: store, contact: buyer)
    Commerce::ContactMetric.create!(account: account, customer_link: link, orders_count: 3, active_orders_count: 0,
                                    spend: { 'SAR' => '1500.00' }, fetched_at: Time.current)
    create(:commerce_customer_link, store: store, contact: unread)
  end

  describe 'POST /contacts/filter' do
    it 'answers the matching contacts, counted and paged, without calling a store' do
      post "/api/v1/accounts/#{account.id}/contacts/filter", headers: agent.create_new_auth_token, params: big_spenders, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['meta']['count']).to eq(1)
      expect(response.parsed_body['payload'].pluck('id')).to eq([buyer.id])
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'answers 422 for a condition it cannot evaluate' do
      payload = { payload: [{ attribute_key: 'commerce_spend_sar', filter_operator: 'is_greater_than', values: [{ 'x' => 1 }] }] }
      post "/api/v1/accounts/#{account.id}/contacts/filter", headers: agent.create_new_auth_token, params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'never evaluates another account\'s contacts' do
      post "/api/v1/accounts/#{account.id}/contacts/filter", headers: other_admin.create_new_auth_token, params: big_spenders, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'saved audiences (contact custom filters)' do
    let(:audience) do
      CustomFilter.create!(account: account, user: admin, name: 'Big spenders', filter_type: :contact, query: big_spenders)
    end

    it 'saves, reads, updates and deletes an audience with Commerce conditions, keeping its contacts' do
      body = { custom_filter: { name: 'Big spenders', filter_type: 'contact', query: big_spenders } }
      post "/api/v1/accounts/#{account.id}/custom_filters", headers: admin.create_new_auth_token, params: body, as: :json
      id = response.parsed_body['id']
      expect(CustomFilter.find(id).query['payload'].first).to include('attribute_key' => 'commerce_spend_sar')

      rename = { custom_filter: { name: 'VIP' } }
      patch "/api/v1/accounts/#{account.id}/custom_filters/#{id}", headers: admin.create_new_auth_token, params: rename, as: :json
      expect(response.parsed_body['name']).to eq('VIP')

      delete "/api/v1/accounts/#{account.id}/custom_filters/#{id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
      expect(account.contacts.count).to eq(2)
    end

    it 'records audience changes in the audit log, and leaves conversation folders out', if: defined?(Enterprise::AuditLog) do
      audience.update!(name: 'VIP')
      audience.destroy!
      CustomFilter.create!(account: account, user: admin, name: 'Open', filter_type: :conversation, query: { payload: [] })

      expect(Enterprise::AuditLog.where(auditable_type: 'CustomFilter').order(:id).pluck(:action, :associated_id))
        .to eq([['create', account.id], ['update', account.id], ['destroy', account.id]])
    end

    it 'is not reachable by another user, nor through another account' do
      get "/api/v1/accounts/#{account.id}/custom_filters/#{audience.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      patch "/api/v1/accounts/#{account.id}/custom_filters/#{audience.id}", headers: agent.create_new_auth_token, as: :json,
                                                                            params: { custom_filter: { name: 'mine' } }
      expect(response).to have_http_status(:not_found)

      get "/api/v1/accounts/#{other_account.id}/custom_filters/#{audience.id}", headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(audience.reload.name).to eq('Big spenders')
    end
  end

  describe 'GET /commerce/audience_fields' do
    let(:path) { "/api/v1/accounts/#{account.id}/commerce/audience_fields" }

    it 'lists the counted stores, the currencies seen and the contacts not read yet, for agents too' do
      create(:commerce_store, account: account, status: :disabled)
      create(:commerce_store, :salla, account: account)

      get path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('stores' => [{ 'id' => store.id, 'name' => 'Syria Cosmetics', 'provider' => 'woocommerce' }],
                                         'currencies' => ['SAR'], 'unread_contacts' => 1)
      expect(response.body).not_to include('base_url', 'credentials', 'ck_factory')
    end

    it 'is unavailable without Lynomia Commerce and to other accounts' do
      get path, headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      account.disable_features!('lynomia_commerce')
      get path, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
