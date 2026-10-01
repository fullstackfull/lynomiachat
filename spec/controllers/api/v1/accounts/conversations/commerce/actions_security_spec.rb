require 'rails_helper'

# The action and cart security cases not covered next to their features (docs/commerce/32-actions-security.md §tests):
# another store's order or cart through this store, a key replayed from another account, a provider switched off.
RSpec.describe 'Commerce actions security', type: :request do
  include_context 'with commerce encryption'
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:orders) { JSON.parse(file_fixture('commerce/woocommerce/orders.json').read).index_by { |order| order['id'] } }
  let(:store_a) { create_store.call('shop-a.example.com') }
  let(:store_b) { create_store.call('shop-b.example.com') }
  let(:create_store) do
    lambda do |host|
      create(:commerce_store, account: account, base_url: "https://#{host}", external_store_id: host, metadata: { 'write_access' => 'granted' },
                              settings: { 'order_actions' => true })
    end
  end
  let(:base_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce" }
  let(:actions_path) { ->(store, order_id) { "#{base_path}/stores/#{store.id}/orders/#{order_id}/actions" } }
  let(:refund_body) do
    lambda do |key|
      { action_type: 'refund_partial', version: 'a' * 32, idempotency_key: key, params: { amount: '1.00', currency: 'SAR', reason: 'other' } }
    end
  end

  before do
    account.enable_features!('lynomia_commerce')
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with(/shop-[ab]\.example\.com/).and_return(['93.184.216.34'])
    [store_a, store_b].each do |store|
      create(:commerce_customer_link, store: store, account: account, contact: contact, external_customer_id: '2', match_source: :manual)
    end
    stub_request(:get, %r{shop-a\.example\.com/wp-json/wc/v3/orders\?}).to_return(status: 200, body: [orders[15]].to_json)
    stub_request(:get, %r{shop-b\.example\.com/wp-json/wc/v3/orders\?}).to_return(status: 200, body: [orders[14]].to_json)
  end

  it 'never reads or acts on another store\'s order through this store' do
    get actions_path.call(store_b, 15), headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('error' => { 'code' => 'NOT_FOUND' })
    expect(a_request(:get, 'https://shop-b.example.com/wp-json/wc/v3/orders/15')).not_to have_been_made
    expect(a_request(:get, /shop-a\.example\.com/)).not_to have_been_made
  end

  it 'answers a key replayed from another account with a conflict, never with that account\'s run' do
    key = "commerce-action:#{SecureRandom.uuid}"
    other_store = create(:commerce_store)
    Commerce::ActionRun.create!(account: other_store.account, store: other_store, provider: 'woocommerce', action_type: 'refund_partial',
                                external_resource_id: '15', idempotency_key: key, request_digest: 'd' * 64)

    post actions_path.call(store_a, 15), params: refund_body.call(key), headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('error' => { 'code' => 'IDEMPOTENCY_CONFLICT' })
    expect(Commerce::ActionRun.where(account: account)).to be_empty
  end

  it 'reaches no store of a provider the installation switched off' do
    zid = create(:commerce_store, :zid, account: account, settings: { 'order_actions' => true })

    get actions_path.call(zid, 41_000_101), headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    post "#{base_path}/stores/#{zid.id}/carts/c0ffee01/recovery", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'settles a run whose job was lost without sending it, and reconciles one left without an answer' do
    run = lambda do |action_type, **attributes|
      prefix = action_type == 'recovery_message' ? 'commerce-recovery' : 'commerce-action'
      Commerce::ActionRun.create!(account: account, store: store_a, provider: 'woocommerce', action_type: action_type, external_resource_id: '15',
                                  idempotency_key: "#{prefix}:#{SecureRandom.uuid}", request_digest: SecureRandom.hex(32), **attributes)
    end
    lost = run.call('refund_partial', created_at: 11.minutes.ago)
    silent = run.call('cancel_order', status: :unknown, started_at: 20.minutes.ago, updated_at: 16.minutes.ago)
    prepared = run.call('recovery_message', created_at: 91.days.ago)

    expect { Commerce::ActionSweepJob.perform_now }.to have_enqueued_job(Commerce::ActionReconcileJob).with(silent.id)

    expect(lost.reload).to have_attributes(status: 'failed', error_code: 'NOT_SENT')
    expect(Commerce::ActionRun.exists?(prepared.id)).to be(false)
    expect(a_request(:post, /refunds/)).not_to have_been_made
    expect(Commerce::ActionJob).not_to have_been_enqueued
  end
end
