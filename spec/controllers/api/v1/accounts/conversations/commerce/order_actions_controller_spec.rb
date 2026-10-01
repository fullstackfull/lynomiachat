require 'rails_helper'

# Order action endpoints (docs/commerce/28-commerce-actions-architecture.md): scope, permissions, idempotency, rate limits.
# The provider is stubbed (spec/support/commerce_actions.rb); WooCommerce's own actions have their own specs.
RSpec.describe 'Commerce order actions API', type: :request do
  include_context 'with commerce order actions'

  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce" }
  let(:actions_path) { "#{base_path}/stores/#{store.id}/orders/501/actions" }
  let(:body) do
    { action_type: 'refund_partial', version: version, idempotency_key: key,
      params: { amount: '40.00', currency: 'SAR', reason: 'customer_request' } }
  end

  before do
    account.enable_features!('lynomia_commerce')
    create(:inbox_member, user: agent, inbox: inbox)
  end

  it 'tells an agent of the conversation what is possible, without performing anything' do
    get actions_path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('version' => version, 'store' => { 'id' => store.id, 'name' => store.name, 'provider' => 'woocommerce' })
    expect(response.parsed_body['actions']['refund_partial']).to eq('available' => false, 'reason' => 'permission_denied')
    expect(provider).not_to receive(:perform_action)
  end

  it 'accepts an administrator\'s refund once, however often it is submitted' do
    2.times { post actions_path, params: body, headers: admin.create_new_auth_token, as: :json }

    expect(response).to have_http_status(:accepted)
    run = Commerce::ActionRun.sole
    expect(response.parsed_body).to include('id' => run.id, 'status' => 'pending', 'action_type' => 'refund_partial', 'amount' => '40.00',
                                            'currency' => 'SAR', 'order_id' => '501', 'store_id' => store.id)
    expect(response.parsed_body.keys).not_to include('idempotency_key', 'request_digest', 'metadata', 'contact_id')
    expect(Commerce::ActionJob).to have_been_enqueued.once

    get "#{base_path}/action_runs/#{run.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('id' => run.id, 'status' => 'pending')
  end

  it 'refuses a refund from an agent, and the forged availability the browser might claim' do
    post actions_path, params: body, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(Commerce::ActionRun.count).to eq(0)
  end

  it 'reaches only the account\'s active stores and the conversation\'s own runs' do
    other_store = create(:commerce_store, settings: { 'order_actions' => true })
    get "#{base_path}/stores/#{other_store.id}/orders/501/actions", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    store.update!(status: :needs_reauth)
    post actions_path, params: body, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    other_run = Commerce::ActionRun.create!(account: account, store: store, provider: 'woocommerce', action_type: 'refund_full',
                                            external_resource_id: '501', idempotency_key: key, request_digest: 'd' * 64,
                                            conversation: create(:conversation, account: account, inbox: inbox))
    get "#{base_path}/action_runs/#{other_run.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'is not reachable from another account' do
    other_admin = create(:user, account: create(:account), role: :administrator)

    get actions_path, headers: other_admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'answers invalid input with 422 and a code' do
    post actions_path, params: body.merge(params: { amount: '1e9', currency: 'SAR', reason: 'other' }),
                       headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => { 'code' => 'INVALID_AMOUNT' })
  end

  it 'limits an agent\'s requests with 429 and Retry-After' do
    Redis::Alfred.set("COMMERCE::ACTION_RATE::ACCOUNT::#{account.id}::USER::#{admin.id}", 10, ex: 40)

    post actions_path, params: body, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers['Retry-After'].to_i).to be_between(1, 40)
    expect(response.parsed_body['error']).to include('code' => 'RATE_LIMITED')
  end

  it 'offers the actions menu only where it can work, and only to whoever may use it' do
    get "#{base_path}/stores", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].sole).to include('id' => store.id, 'actions' => true)

    get "#{base_path}/stores", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].sole).to include('actions' => false)

    store.update!(settings: {})
    get "#{base_path}/stores", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].sole).to include('actions' => false)
  end
end
