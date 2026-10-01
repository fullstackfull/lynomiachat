require 'rails_helper'

# WooCommerce order actions through the API, end to end inside Lynomia (docs/commerce/32-actions-security.md §tests): the
# store answers with captured WooCommerce 10.9.4 payloads, everything on Lynomia's side runs for real.
RSpec.describe 'WooCommerce order actions', type: :request do
  include_context 'with commerce encryption'
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:store) do
    create(:commerce_store, account: account, base_url: 'https://shop.example.com', external_store_id: 'shop.example.com',
                            metadata: { 'write_access' => 'granted' }, settings: { 'order_actions' => true })
  end
  let(:api) { 'https://shop.example.com/wp-json/wc/v3' }
  let(:orders) { JSON.parse(file_fixture('commerce/woocommerce/orders.json').read).index_by { |order| order['id'] } }
  let(:actions_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/stores/#{store.id}/orders/15/actions" }
  let(:refund_stub) { stub_request(:post, "#{api}/orders/15/refunds").to_return(status: 201, body: { id: 31 }.to_json) }
  let(:availability) do
    lambda do |user = admin|
      get actions_path, headers: user.create_new_auth_token, as: :json
      response.parsed_body
    end
  end
  let(:refund) do
    lambda do |version, amount: '29.25', key: "commerce-action:#{SecureRandom.uuid}", user: admin|
      post actions_path, headers: user.create_new_auth_token, as: :json,
                         params: { action_type: 'refund_partial', version: version, idempotency_key: key,
                                   params: { amount: amount, currency: 'SAR', reason: 'customer_request' } }
      response.parsed_body
    end
  end

  before do
    account.enable_features!('lynomia_commerce')
    create(:inbox_member, user: agent, inbox: inbox)
    create(:commerce_customer_link, store: store, account: account, contact: contact, external_customer_id: '2', match_source: :verified_phone)
    allow(Resolv).to receive(:getaddresses).with('shop.example.com').and_return(['93.184.216.34'])
    stub_request(:get, "#{api}/orders").with(query: hash_including('customer' => '2'))
                                       .to_return(status: 200, body: orders.values.select { |order| order['customer_id'] == 2 }.to_json)
    stub_request(:get, "#{api}/orders/15").to_return(status: 200, body: orders[15].to_json)
    stub_request(:get, "#{api}/payment_gateways/stripe").to_return(status: 200, body: { enabled: true, method_supports: %w[refunds] }.to_json)
    refund_stub
  end

  it 'refunds once however often the agent confirms, then reads the order again' do
    version = availability.call['version']
    key = "commerce-action:#{SecureRandom.uuid}"
    runs = Array.new(2) { refund.call(version, key: key)['id'] }

    expect(runs.uniq.size).to eq(1)
    perform_enqueued_jobs(only: Commerce::ActionJob)

    expect(refund_stub).to have_been_requested.once
    expect(Commerce::ActionRun.sole).to have_attributes(status: 'succeeded', provider_request_id: '31', requested_by: admin)
    expect(Commerce::RefreshJob).to have_been_enqueued
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/action_runs/#{runs.first}",
        headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('status' => 'succeeded', 'amount' => '29.25', 'mode' => 'gateway', 'order_number' => '15')
  end

  it 'stops when the order changed after the agent confirmed (a stale order)' do
    version = availability.call['version']
    stub_request(:get, "#{api}/orders/15").to_return(status: 200, body: orders[15].merge('refunds' => [{ 'id' => 30, 'total' => '-50.00' }]).to_json)

    refund.call(version)
    perform_enqueued_jobs(only: Commerce::ActionJob)

    expect(Commerce::ActionRun.sole).to have_attributes(status: 'failed', error_code: 'ORDER_CHANGED')
    expect(refund_stub).not_to have_been_requested
  end

  it 'never refunds more than WooCommerce says is refundable, whatever the browser sends' do
    refund.call(availability.call['version'], amount: '79.26')
    perform_enqueued_jobs(only: Commerce::ActionJob)

    expect(Commerce::ActionRun.sole).to have_attributes(status: 'failed', error_code: 'INVALID_AMOUNT')
    expect(refund_stub).not_to have_been_requested
  end

  it 'refuses another order id than the linked customer\'s, and other accounts' do
    stub_request(:get, "#{api}/orders/26").to_return(status: 200, body: orders[26].to_json)
    get actions_path.sub('/orders/15/', '/orders/26/'), headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('error' => { 'code' => 'NOT_FOUND' })

    stranger = create(:user, account: create(:account), role: :administrator)
    refund.call('a' * 32, user: stranger)
    expect(response).to have_http_status(:unauthorized)
    expect(a_request(:get, "#{api}/orders/26")).not_to have_been_made
  end

  it 'marks a lost answer unknown and settles it from the store\'s refunds, never sending it again' do
    lost = stub_request(:post, "#{api}/orders/15/refunds").to_raise(Net::ReadTimeout)
    key = "commerce-action:#{SecureRandom.uuid}"
    refund.call(availability.call['version'], key: key)
    perform_enqueued_jobs(only: Commerce::ActionJob)
    run = Commerce::ActionRun.sole
    expect(run).to have_attributes(status: 'unknown', error_code: 'UNKNOWN_OUTCOME')

    refunds = [{ id: 31, meta_data: [{ key: 'lynomia_action_key', value: key }] }]
    stub_request(:get, "#{api}/orders/15/refunds").with(query: { per_page: 100 }).to_return(status: 200, body: refunds.to_json)
    perform_enqueued_jobs(only: Commerce::ActionReconcileJob)

    expect(run.reload).to have_attributes(status: 'succeeded', provider_request_id: '31')
    expect(lost).to have_been_requested.once
  end

  it 'keeps refunds administrator-only, and honors the installation switch' do
    expect(availability.call(agent)['actions']['refund_partial']).to eq('available' => false, 'reason' => 'permission_denied')
    refund.call('a' * 32, user: agent)
    expect(response).to have_http_status(:unauthorized)

    with_modified_env(WOOCOMMERCE_ACTIONS_ENABLED: 'false') { refund.call('a' * 32) }
    expect(response.parsed_body).to eq('error' => { 'code' => 'ACTIONS_DISABLED', 'reason' => 'provider_actions_disabled' })
    expect(Commerce::ActionRun.count).to eq(0)
  end

  it 'reaches no store that needs re-authorization' do
    store.update!(status: :needs_reauth)

    availability.call
    expect(response).to have_http_status(:not_found)
  end

  describe 'the store administrator\'s opt-in' do
    let(:opt_in) do
      lambda do |value, user = admin|
        patch "/api/v1/accounts/#{account.id}/commerce/stores/#{store.id}",
              params: { order_actions: value }, headers: user.create_new_auth_token, as: :json
        response.parsed_body
      end
    end

    before { store.update!(settings: {}) }

    it 'needs a Read/Write key and never upgrades a Read key' do
      store.update!(metadata: { 'realtime' => { 'status' => 'read_only_key' }, 'write_access' => 'read_only_key' })
      expect(opt_in.call(true)).to eq('error' => { 'code' => 'WRITE_ACCESS_DENIED', 'reason' => 'read_only_key' })
      expect(store.reload.settings).to eq({})
      expect(store.credentials).to eq('consumer_key' => 'ck_factory', 'consumer_secret' => 'cs_factory')

      store.update!(metadata: { 'write_access' => 'granted' })
      expect(opt_in.call(true)).to include('order_actions' => true, 'order_actions_status' => 'available')
      expect(opt_in.call(false)).to include('order_actions' => false, 'order_actions_status' => 'available')
      expect(a_request(:any, /shop\.example\.com/)).not_to have_been_made
    end

    it 'is for administrators only and accepts only true or false' do
      opt_in.call(true, agent)
      expect(response).to have_http_status(:unauthorized)

      opt_in.call('yes')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(store.reload.settings).to eq({})
    end
  end
end
