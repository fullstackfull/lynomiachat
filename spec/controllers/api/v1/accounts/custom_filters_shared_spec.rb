require 'rails_helper'

# Lynomia shared audiences on Chatwoot's saved filters API (docs/automation/02-shared-audiences.md).
RSpec.describe 'Shared audiences API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:query) { { payload: [{ attribute_key: 'email', filter_operator: 'contains', values: ['example.com'] }] } }
  let(:shared) { create(:custom_filter, account: account, user: admin, filter_type: :contact, name: 'VIP', shared: true, query: query) }
  let(:base) { "/api/v1/accounts/#{account.id}/custom_filters" }

  def reference(audience, active: true)
    rule = account.automation_rules.new(name: 'VIP rule', event_name: 'conversation_created', active: active, actions: [],
                                        conditions: [{ 'attribute_key' => 'contact_audience', 'filter_operator' => 'equal_to',
                                                       'values' => [audience.id], 'query_operator' => nil }])
    rule.save!(validate: false)
    rule
  end

  it 'lists a member\'s own filters and the account\'s shared audiences, never another member\'s personal ones' do
    mine = create(:custom_filter, account: account, user: agent, filter_type: :contact, query: query)
    create(:custom_filter, account: account, user: other_agent, filter_type: :contact, query: query)
    shared

    get base, headers: agent.create_new_auth_token, params: { filter_type: 'contact' }, as: :json

    expect(response.parsed_body.pluck('id')).to contain_exactly(mine.id, shared.id)
    expect(response.parsed_body.find { |filter| filter['id'] == shared.id }).to include('shared' => true, 'automation_rules_count' => 0)
    expect(response.parsed_body.find { |filter| filter['id'] == mine.id }['shared']).to be(false)
  end

  it 'keeps existing filters personal: nothing is shared unless an administrator asks' do
    post base, headers: agent.create_new_auth_token, params: { custom_filter: { name: 'Mine', filter_type: 'contact', query: query } }, as: :json

    expect(response).to have_http_status(:ok)
    expect(CustomFilter.find(response.parsed_body['id']).shared).to be(false)
  end

  it 'lets only administrators share, change or delete a shared audience; agents may open it' do
    post base, headers: agent.create_new_auth_token,
               params: { custom_filter: { name: 'Shared', filter_type: 'contact', shared: true, query: query } }, as: :json
    expect(response).to have_http_status(:unauthorized)

    patch "#{base}/#{shared.id}", headers: agent.create_new_auth_token, params: { custom_filter: { name: 'Mine now' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    delete "#{base}/#{shared.id}", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    get "#{base}/#{shared.id}", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['query']).to eq(query.deep_stringify_keys)

    post base, headers: admin.create_new_auth_token,
               params: { custom_filter: { name: 'Shared', filter_type: 'contact', shared: true, query: query } }, as: :json
    expect(CustomFilter.find(response.parsed_body['id'])).to have_attributes(shared: true, user_id: admin.id)
    expect(shared.reload.name).to eq('VIP')
  end

  it 'shares contact audiences only, not conversation folders' do
    post base, headers: admin.create_new_auth_token,
               params: { custom_filter: { name: 'Open', filter_type: 'conversation', shared: true, query: query } }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'refuses to delete or unshare an audience automation rules use, and says how many' do
    reference(shared)
    reference(shared, active: false)

    delete "#{base}/#{shared.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('2 automation rules')

    patch "#{base}/#{shared.id}", headers: admin.create_new_auth_token, params: { custom_filter: { shared: false } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(shared.reload.shared).to be(true)

    get "#{base}/#{shared.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('automation_rules_count' => 2, 'active_automation_rules_count' => 1)

    patch "#{base}/#{shared.id}", headers: admin.create_new_auth_token, params: { custom_filter: { query: query } }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'deletes an unused shared audience' do
    delete "#{base}/#{shared.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(CustomFilter.exists?(shared.id)).to be(false)
  end

  it 'keeps a shared audience with the account when its creator is deleted, and their personal filters go' do
    personal = create(:custom_filter, account: account, user: admin, filter_type: :contact, query: query)
    shared

    admin.destroy!
    perform_enqueued_jobs(only: ActiveRecord::DestroyAssociationAsyncJob)

    expect(shared.reload.user_id).to be_nil
    expect(CustomFilter.exists?(personal.id)).to be(false)

    other_admin = create(:user, account: account, role: :administrator)
    patch "#{base}/#{shared.id}", headers: other_admin.create_new_auth_token, params: { custom_filter: { name: 'VIP buyers' } }, as: :json
    expect(shared.reload.name).to eq('VIP buyers')
  end

  it 'never shows or changes another account\'s shared audience' do
    other_admin = create(:user, account: create(:account), role: :administrator)
    other_base = "/api/v1/accounts/#{other_admin.accounts.first.id}/custom_filters"

    get "#{other_base}/#{shared.id}", headers: other_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    get other_base, headers: other_admin.create_new_auth_token, params: { filter_type: 'contact' }, as: :json
    expect(response.parsed_body).to be_empty
    get "#{base}/#{shared.id}", headers: other_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
