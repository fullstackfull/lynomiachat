require 'rails_helper'

# Zid order actions (docs/commerce/29-provider-action-capabilities.md §Zid): two status steps of Zid's own flow, through
# the change-order-status endpoint its official SDK documents. Nothing else is offered.
RSpec.describe Commerce::Providers::Zid::Actions do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:store) { create(:commerce_store, :zid, external_store_id: '318001', metadata: { 'time_zone' => 'Asia/Riyadh' }) }
  let(:provider) { Commerce::Providers.for(store) }
  let(:api) { 'https://api.zid.sa/v1/managers/store/orders' }
  let(:order) { JSON.parse(file_fixture('commerce/zid/orders.json').read)['orders'].first }
  let(:with_code) { ->(code) { order.merge('order_status' => order['order_status'].merge('code' => code)) } }
  let(:snapshot) do
    lambda do |code|
      stub_request(:get, "#{api}/#{order['id']}/view").to_return(status: 200, body: { order: with_code.call(code) }.to_json)
      provider.action_snapshot(order['id'].to_s)
    end
  end
  let(:key) { "commerce-action:#{SecureRandom.uuid}" }

  it 'offers ready → shipped and in delivery → delivered only, and nothing else' do
    expect(snapshot.call('ready').capabilities).to eq('update_order_status' => { available: true, targets: %w[shipped] })
    expect(snapshot.call('indelivery').capabilities).to eq('update_order_status' => { available: true, targets: %w[delivered] })
    %w[new preparing delivered cancelled].each do |code|
      expect(snapshot.call(code).capabilities).to eq('update_order_status' => { available: false, reason: 'order_state' })
    end
  end

  it 'changes the status once and checks Zid\'s answer' do
    delivered = { order: with_code.call('delivered') }
    change = stub_request(:post, "#{api}/#{order['id']}/change-order-status").with(body: { order_status: 'delivered' }.to_json)
                                                                             .to_return(status: 200, body: delivered.to_json)

    result = provider.perform_action('update_order_status', snapshot.call('indelivery'), { 'target_status' => 'delivered' }, key)

    expect(result).to eq(Commerce::ActionResult.succeeded)
    expect(change).to have_been_requested.once
  end

  it 'learns from a 403 that the authorization lacks the permission, and refuses other answers without retrying' do
    endpoint = stub_request(:post, "#{api}/#{order['id']}/change-order-status")
    snap = snapshot.call('ready')
    { 403 => Commerce::ActionResult.failed('WRITE_ACCESS_DENIED'), 422 => Commerce::ActionResult.failed('PROVIDER_REJECTED'),
      502 => Commerce::ActionResult.unknown }.each do |status, expected|
      endpoint.to_return(status: status, body: '{}')
      expect(provider.perform_action('update_order_status', snap, { 'target_status' => 'shipped' }, key)).to eq(expected)
    end
    expect(endpoint).to have_been_requested.times(3)
    expect(Commerce::Providers.for(store.reload).write_access_problem).to eq('missing_scope')
  end

  it 'settles a lost answer from the order\'s status' do
    run = Commerce::ActionRun.create!(account: store.account, store: store, provider: 'zid', action_type: 'update_order_status',
                                      external_resource_id: order['id'].to_s, idempotency_key: key, request_digest: 'd' * 64,
                                      status: :unknown, started_at: 10.minutes.ago,
                                      metadata: { 'target_status' => 'delivered', 'from_status' => 'shipped' })

    expect(provider.reconcile_action(run, snapshot.call('delivered'))).to eq(Commerce::ActionResult.succeeded)
    expect(provider.reconcile_action(run, snapshot.call('indelivery'))).to eq(Commerce::ActionResult.failed('NOT_APPLIED'))
  end
end
