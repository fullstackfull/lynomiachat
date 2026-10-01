require 'rails_helper'

# WooCommerce order actions (docs/commerce/29-provider-action-capabilities.md §WooCommerce) against the captured
# WooCommerce 10.9.4 order payloads. The real store E2E is docs/commerce/33-phase9-10-e2e.md.
RSpec.describe Commerce::Providers::Woocommerce::Actions do
  include_context 'with commerce encryption'

  let(:store) do
    create(:commerce_store, base_url: 'https://shop.example.com', external_store_id: 'shop.example.com', metadata: { 'write_access' => 'granted' })
  end
  let(:provider) { Commerce::Providers.for(store) }
  let(:api) { 'https://shop.example.com/wp-json/wc/v3' }
  let(:orders) { JSON.parse(file_fixture('commerce/woocommerce/orders.json').read).index_by { |order| order['id'] } }
  let(:key) { "commerce-action:#{SecureRandom.uuid}" }
  let(:stub_order) { ->(raw) { stub_request(:get, "#{api}/orders/#{raw['id']}").to_return(status: 200, body: raw.to_json) } }
  let(:stub_gateway) do
    lambda do |supports, status: 200|
      stub_request(:get, "#{api}/payment_gateways/stripe")
        .to_return(status: status, body: { id: 'stripe', enabled: true, method_supports: supports }.to_json)
    end
  end
  let(:snapshot_of) do
    lambda do |raw|
      stub_order.call(raw)
      provider.action_snapshot(raw['id'].to_s)
    end
  end
  let(:run) do
    lambda do |action_type, metadata = {}|
      Commerce::ActionRun.create!(account: store.account, store: store, provider: 'woocommerce', action_type: action_type,
                                  external_resource_id: '15', idempotency_key: key, request_digest: 'd' * 64, status: :unknown,
                                  started_at: 10.minutes.ago, metadata: metadata)
    end
  end

  before do
    allow(Resolv).to receive(:getaddresses).with('shop.example.com').and_return(['93.184.216.34'])
    stub_gateway.call(%w[products refunds])
  end

  describe 'capabilities' do
    it 'offers a paid processing order its refunds through the gateway, two status changes, the invoice, and no cancellation' do
      snapshot = snapshot_of.call(orders[15])

      expect(snapshot.order.external_order_id).to eq('15')
      expect(snapshot.version).to match(/\A\h{32}\z/)
      expect(snapshot.capabilities).to eq(
        'update_order_status' => { available: true, targets: %w[completed on_hold] },
        'cancel_order' => { available: false, reason: 'paid_refund_first' },
        'refund_full' => { available: true, max_amount: '79.25', currency: 'SAR', mode: 'gateway', gateway: orders[15]['payment_method_title'] },
        'refund_partial' => { available: true, max_amount: '79.25', currency: 'SAR', mode: 'gateway', gateway: orders[15]['payment_method_title'] },
        'resend_invoice' => { available: true }, 'resend_payment_link' => { available: false, reason: 'order_state' }
      )
    end

    it 'refunds only what is left, and nothing once the order is fully refunded' do
      partially = orders[15].merge('refunds' => [{ 'id' => 31, 'reason' => '', 'total' => '-29.25' }])
      expect(snapshot_of.call(partially).capabilities['refund_partial']).to include(available: true, max_amount: '50.00')

      fully = orders[15].merge('refunds' => [{ 'id' => 31, 'reason' => '', 'total' => '-79.25' }])
      expect(snapshot_of.call(fully).capabilities['refund_full']).to eq(available: false, reason: 'nothing_refundable')
      expect(snapshot_of.call(orders[18]).capabilities['refund_full']).to eq(available: false, reason: 'not_paid')
    end

    it 'records the refund only when the gateway cannot send money back, or cannot be read' do
      stub_gateway.call(%w[products])
      expect(snapshot_of.call(orders[15]).capabilities['refund_full']).to include(available: true, mode: 'manual')

      stub_gateway.call([], status: 403)
      expect(snapshot_of.call(orders[15]).capabilities['refund_full']).to include(available: true, mode: 'manual')
      expect(snapshot_of.call(orders[15]).capabilities['refund_full']).not_to have_key(:gateway)
    end

    it 'never refunds an unpaid order: cash on delivery not yet collected, pending, on-hold' do
      [orders[22], orders[23], orders[17]].each do |raw|
        expect(snapshot_of.call(raw).capabilities['refund_partial']).to eq(available: false, reason: 'not_paid')
      end
    end

    it 'cancels unpaid orders only, restocking without refunding, and offers their payment link' do
      pending_order = snapshot_of.call(orders[23]).capabilities
      expect(pending_order['cancel_order']).to eq(available: true, restocks: true, refunds: false)
      expect(pending_order['resend_payment_link']).to eq(available: true)
      on_hold = snapshot_of.call(orders[17]).capabilities
      expect(on_hold).to include('cancel_order' => { available: true, restocks: true, refunds: false },
                                 'update_order_status' => { available: true, targets: %w[processing] })
      expect(snapshot_of.call(orders[16]).capabilities['cancel_order']).to eq(available: false, reason: 'already_cancelled')
      expect(snapshot_of.call(orders[14]).capabilities['update_order_status']).to eq(available: false, reason: 'order_state')
    end

    it 'offers no email without a billing email' do
      raw = orders[15].merge('billing' => orders[15]['billing'].merge('email' => ''))

      expect(snapshot_of.call(raw).capabilities['resend_invoice']).to eq(available: false, reason: 'no_email')
    end

    it 'changes its version with status, totals or refunds only' do
      version = snapshot_of.call(orders[15]).version

      expect(snapshot_of.call(orders[15].merge('date_modified_gmt' => '2026-10-01T00:00:00', 'customer_note' => 'x')).version).to eq(version)
      expect(snapshot_of.call(orders[15].merge('status' => 'completed')).version).not_to eq(version)
      expect(snapshot_of.call(orders[15].merge('refunds' => [{ 'id' => 31, 'total' => '-1.00' }])).version).not_to eq(version)
    end
  end

  describe 'performing' do
    let(:snapshot) { snapshot_of.call(orders[15]) }
    let(:refund_params) { { 'amount' => '29.25', 'currency' => 'SAR', 'reason' => 'damaged' } }

    it 'refunds once, through the gateway, with the run\'s key, nothing restocked' do
      refund = stub_request(:post, "#{api}/orders/15/refunds")
               .with(body: { amount: '29.25', reason: 'Lynomia: Damaged item', api_refund: true, api_restock: false,
                             meta_data: [{ key: 'lynomia_action_key', value: key }] }.to_json)
               .to_return(status: 201, body: { id: 31, amount: '29.25' }.to_json)

      result = provider.perform_action('refund_partial', snapshot, refund_params, key)

      expect(result).to eq(Commerce::ActionResult.succeeded('31'))
      expect(refund).to have_been_requested.once
    end

    it 'classifies the store\'s answers without retrying any of them' do
      refunds = stub_request(:post, "#{api}/orders/15/refunds")
      {
        [500, { code: 'woocommerce_rest_cannot_create_order_refund', message: 'No' }] => Commerce::ActionResult.failed('REFUND_DECLINED'),
        [400, { code: 'woocommerce_rest_invalid_order_refund' }] => Commerce::ActionResult.failed('PROVIDER_REJECTED'),
        [404, { code: 'woocommerce_rest_invalid_order_id' }] => Commerce::ActionResult.failed('NOT_FOUND'),
        [502, nil] => Commerce::ActionResult.unknown, [500, nil] => Commerce::ActionResult.unknown
      }.each do |(status, body), expected|
        refunds.to_return(status: status, body: body.to_json)
        expect(provider.perform_action('refund_partial', snapshot, refund_params, key)).to eq(expected)
      end
      expect(refunds).to have_been_requested.times(5)
    end

    it 'reports a lost answer as unknown outcome, sent once' do
      refunds = stub_request(:post, "#{api}/orders/15/refunds").to_raise(Net::ReadTimeout)

      expect { provider.perform_action('refund_partial', snapshot, refund_params, key) }.to raise_error(Commerce::Error) { |error|
        expect(error.as_json).to eq(code: 'TIMEOUT', reason: 'unknown_outcome')
      }
      expect(refunds).to have_been_requested.once
    end

    it 'learns that the key cannot write, and says so from then on' do
      stub_request(:post, "#{api}/orders/15/refunds").to_return(status: 401, body: { code: 'woocommerce_rest_authentication_error' }.to_json)

      expect(provider.perform_action('refund_partial', snapshot, refund_params, key)).to eq(Commerce::ActionResult.failed('WRITE_ACCESS_DENIED'))
      expect(store.reload.metadata['write_access']).to eq('read_only_key')
      expect(Commerce::Providers.for(store).write_access_problem).to eq('read_only_key')
      expect(store).to be_active
    end

    it 'changes the status to an allow-listed one, and cancels as a status change' do
      completed = stub_request(:put, "#{api}/orders/15").with(body: { status: 'completed' }.to_json)
                                                        .to_return(status: 200, body: orders[15].merge('status' => 'completed').to_json)
      on_hold = stub_request(:put, "#{api}/orders/15").with(body: { status: 'on-hold' }.to_json)
                                                      .to_return(status: 200, body: orders[15].merge('status' => 'processing').to_json)

      change = ->(target) { provider.perform_action('update_order_status', snapshot, { 'target_status' => target }, key) }
      expect(change.call('completed')).to eq(Commerce::ActionResult.succeeded('15'))
      expect(change.call('on_hold')).to eq(Commerce::ActionResult.unknown)
      expect([completed, on_hold]).to all(have_been_requested.once)

      cancel = stub_request(:put, "#{api}/orders/23").with(body: { status: 'cancelled' }.to_json)
                                                     .to_return(status: 200, body: orders[23].merge('status' => 'cancelled').to_json)
      cancelled = provider.perform_action('cancel_order', snapshot_of.call(orders[23]), { 'reason' => 'other' }, key)
      expect(cancelled).to eq(Commerce::ActionResult.succeeded('23'))
      expect(cancel).to have_been_requested.once
    end

    it 'resends WooCommerce\'s order details email without touching the billing email' do
      email = stub_request(:post, "#{api}/orders/15/actions/send_order_details").with(body: '{}')
                                                                                .to_return(status: 200, body: { message: 'sent' }.to_json)

      expect(provider.perform_action('resend_invoice', snapshot, {}, key)).to eq(Commerce::ActionResult.succeeded)
      expect(email).to have_been_requested.once
    end
  end

  describe 'reconciling' do
    let(:snapshot) { snapshot_of.call(orders[15]) }
    let(:refunds) do
      ->(list) { stub_request(:get, "#{api}/orders/15/refunds").with(query: { per_page: 100 }).to_return(status: 200, body: list.to_json) }
    end

    it 'finds the refund by the run\'s key' do
      ours = { id: 31, date_created_gmt: 9.minutes.ago.utc.iso8601.delete('Z'), meta_data: [{ id: 77, key: 'lynomia_action_key', value: key }] }
      refunds.call([{ id: 30, date_created_gmt: 1.day.ago.utc.iso8601.delete('Z'), meta_data: [] }, ours])

      expect(provider.reconcile_action(run.call('refund_partial'), snapshot)).to eq(Commerce::ActionResult.succeeded('31'))
    end

    it 'calls a refund not applied only once WordPress must have finished and no refund appeared since' do
      refunds.call([{ id: 30, date_created_gmt: 1.day.ago.utc.iso8601.delete('Z'), meta_data: [] }])
      expect(provider.reconcile_action(run.call('refund_partial'), snapshot)).to eq(Commerce::ActionResult.failed('NOT_APPLIED'))

      Commerce::ActionRun.delete_all
      recent = run.call('refund_partial').tap { |item| item.update!(started_at: 1.minute.ago) }
      expect(provider.reconcile_action(recent, snapshot)).to eq(Commerce::ActionResult.unknown)
    end

    it 'stays unknown while a refund created since the send has no key yet' do
      refunds.call([{ id: 32, date_created_gmt: 9.minutes.ago.utc.iso8601.delete('Z'), meta_data: [] }])

      expect(provider.reconcile_action(run.call('refund_partial'), snapshot)).to eq(Commerce::ActionResult.unknown)
    end

    it 'reads a status change from the order' do
      status_run = run.call('update_order_status', 'target_status' => 'completed', 'from_status' => 'processing')
      completed = snapshot_of.call(orders[15].merge('status' => 'completed'))
      expect(provider.reconcile_action(status_run, completed)).to eq(Commerce::ActionResult.succeeded)
      expect(provider.reconcile_action(status_run, snapshot)).to eq(Commerce::ActionResult.failed('NOT_APPLIED'))
      expect(provider.reconcile_action(status_run, snapshot_of.call(orders[15].merge('status' => 'on-hold')))).to eq(Commerce::ActionResult.unknown)
    end

    it 'cannot tell whether an email went out' do
      expect(provider.reconcile_action(run.call('resend_invoice'), snapshot)).to eq(Commerce::ActionResult.unknown('NOT_RECONCILABLE'))
    end
  end

  it 'derives write access from the webhook registration for stores registered before it was recorded' do
    store.update!(metadata: { 'realtime' => { 'status' => 'active' } })
    expect(Commerce::Providers.for(store).write_access_problem).to be_nil

    store.update!(metadata: { 'realtime' => { 'status' => 'read_only_key' } })
    expect(Commerce::Providers.for(store).write_access_problem).to eq('read_only_key')

    store.update!(metadata: {})
    expect(Commerce::Providers.for(store).write_access_problem).to eq('write_access_unverified')
  end
end
