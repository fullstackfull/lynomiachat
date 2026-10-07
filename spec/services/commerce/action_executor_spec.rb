require 'rails_helper'

# Sending an accepted order action, at most once, and settling lost answers by reading the store only
# (docs/commerce/28-commerce-actions-architecture.md §execution, 32-actions-security.md).
RSpec.describe Commerce::ActionExecutor do
  include_context 'with commerce order actions'

  let(:metadata) { { 'amount' => '40.00', 'currency' => 'SAR', 'reason' => 'customer_request', 'version' => version } }
  let(:run) do
    Commerce::ActionRun.create!(account: account, store: store, contact: contact, requested_by: admin, provider: 'woocommerce',
                                action_type: 'refund_partial', external_resource_id: '501', idempotency_key: key, request_digest: 'd' * 64,
                                metadata: metadata)
  end
  let(:execute) { -> { described_class.new(run).call } }
  let(:reconcile) { -> { described_class.new(run.reload).reconcile } }
  let(:check_stall) { -> { described_class.new(run.reload).check_stall } }

  before do
    allow(provider).to receive(:perform_action).and_return(Commerce::ActionResult.succeeded('9001'))
    allow(provider).to receive(:reconcile_action).and_return(Commerce::ActionResult.unknown)
  end

  it 'reads the order again, sends the action once, and shows the store\'s order afterwards' do
    allow(Commerce::Cache).to receive(:invalidate)

    execute.call

    expect(Commerce::RefreshJob).to have_been_enqueued.with(link.id)
    expect(Commerce::ActionReconcileJob).to have_been_enqueued.with(run.id, true)

    expect(provider).to have_received(:action_snapshot).with('501').ordered
    expect(provider).to have_received(:perform_action).with('refund_partial', snapshot, metadata.except('version'), key).once
    expect(run.reload).to have_attributes(status: 'succeeded', provider_request_id: '9001', error_code: nil)
    expect(run.metadata).to include('order_number' => '501', 'mode' => 'gateway',
                                    'result' => { 'status' => 'processing', 'payment_status' => 'paid' })
    expect(Commerce::Cache).to have_received(:invalidate).with(store, :orders, '7')
  end

  it 'never sends a run twice' do
    execute.call
    execute.call
    described_class.new(run.reload).call

    expect(provider).to have_received(:perform_action).once
  end

  it 'stops when the order changed after the agent confirmed' do
    allow(provider).to receive(:action_snapshot).and_return(snapshot.with(version: 'b2' * 8))

    execute.call

    expect(run.reload).to have_attributes(status: 'failed', error_code: 'ORDER_CHANGED')
    expect(provider).not_to have_received(:perform_action)
  end

  it 'stops when the order\'s state no longer allows the action' do
    capabilities['refund_partial'] = { available: false, reason: 'nothing_refundable' }

    execute.call

    expect(run.reload).to have_attributes(status: 'failed', error_code: 'ACTION_UNAVAILABLE')
    expect(provider).not_to have_received(:perform_action)
  end

  it 'never refunds above what the store says is refundable now, in another currency or as a different "full" refund' do
    [['100.01', 'SAR', 'refund_partial'], ['40.00', 'USD', 'refund_partial'], ['40.001', 'SAR', 'refund_partial'],
     ['40.00', 'SAR', 'refund_full']].each do |amount, currency, action_type|
      run.update!(status: :pending, action_type: action_type, metadata: metadata.merge('amount' => amount, 'currency' => currency))
      execute.call
      expect(run.reload).to have_attributes(status: 'failed', error_code: 'INVALID_AMOUNT')
    end
    expect(provider).not_to have_received(:perform_action)
  end

  it 'checks the requester\'s permission and the switches again before sending' do
    admin.account_users.first.update!(role: :agent)
    execute.call
    expect(run.reload).to have_attributes(status: 'failed', error_code: 'PERMISSION_DENIED')

    admin.account_users.first.update!(role: :administrator)
    store.update!(settings: {})
    run.update!(status: :pending)
    execute.call
    expect(run.reload).to have_attributes(status: 'failed', error_code: 'ACTIONS_DISABLED')
    expect(provider).not_to have_received(:perform_action)
  end

  it 'fails safely when the request never reached the store' do
    allow(provider).to receive(:perform_action).and_raise(Commerce::Error.new('STORE_UNAVAILABLE', reason: 'not_sent'))

    execute.call

    expect(run.reload).to have_attributes(status: 'failed', error_code: 'STORE_UNAVAILABLE')
  end

  describe 'a lost answer' do
    before { allow(provider).to receive(:perform_action).and_raise(Commerce::Error.new('TIMEOUT', reason: 'unknown_outcome')) }

    it 'is marked unknown, never sent again, and reconciled by reading the store' do
      expect { execute.call }.to have_enqueued_job(Commerce::ActionReconcileJob).with(run.id).at(a_value_within(2.seconds).of(30.seconds.from_now))

      expect(run.reload).to have_attributes(status: 'unknown', error_code: 'UNKNOWN_OUTCOME')
      allow(provider).to receive(:reconcile_action).and_return(Commerce::ActionResult.succeeded('9001'))
      reconcile.call

      expect(run.reload).to have_attributes(status: 'succeeded', provider_request_id: '9001')
      expect(provider).to have_received(:perform_action).once
      expect(Custom::AuditLog.where(auditable: run).pluck(:comment)).to eq(%w[commerce.action.reconciled])
    end

    it 'is failed once the store shows it did not happen, so the agent can ask again' do
      execute.call
      allow(provider).to receive(:reconcile_action).and_return(Commerce::ActionResult.failed('NOT_FOUND'))
      reconcile.call

      expect(run.reload).to have_attributes(status: 'failed', error_code: 'NOT_APPLIED')
    end

    it 'stays unknown after the last attempt and stops blocking the order' do
      execute.call
      clear_enqueued_jobs

      reconcile.call
      reconcile.call
      expect { reconcile.call }.not_to have_enqueued_job(Commerce::ActionReconcileJob)

      expect(run.reload).to have_attributes(status: 'unknown')
      expect(run.metadata).to include('reconcile_attempts' => 3, 'reconcile' => 'exhausted')
      expect(provider).to have_received(:perform_action).once
    end
  end

  it 'marks a run unknown when its worker died while sending it' do
    run.update!(status: :running, started_at: 3.minutes.ago)

    expect { check_stall.call }.to have_enqueued_job(Commerce::ActionReconcileJob).with(run.id)
    expect(run.reload).to be_unknown
    expect(provider).not_to have_received(:perform_action)
  end

  it 'follows a store job until the store shows the result' do
    allow(provider).to receive(:perform_action).and_return(Commerce::ActionResult.running('gid://shopify/Job/1'))

    expect { execute.call }.to have_enqueued_job(Commerce::ActionReconcileJob).with(run.id).at(a_value_within(2.seconds).of(30.seconds.from_now))
    expect(run.reload).to have_attributes(status: 'running', provider_request_id: 'gid://shopify/Job/1')

    check_stall.call
    expect(run.reload).to be_running

    allow(provider).to receive(:reconcile_action).and_return(Commerce::ActionResult.succeeded)
    reconcile.call
    expect(run.reload).to have_attributes(status: 'succeeded', provider_request_id: 'gid://shopify/Job/1')
  end
end
