require 'rails_helper'

# The provider-neutral checks before an order action is accepted (docs/commerce/28-commerce-actions-architecture.md,
# 32-actions-security.md): switches, opt-in, credentials, permission, ownership, idempotency, rate limits, input shape.
RSpec.describe Commerce::OrderActions do
  include_context 'with commerce order actions'

  let(:actions_for) do
    lambda do |user = admin|
      described_class.new(store: store, contact_id: contact.id, user: user, account_user: account.account_users.find_by(user: user))
    end
  end
  let(:refund) do
    lambda do |user: admin, idempotency_key: key, amount: '40.00', **overrides|
      params = { amount: amount, currency: 'SAR', reason: 'customer_request' }.merge(overrides.fetch(:params, {}))
      actions_for.call(user).request(overrides.fetch(:action_type, 'refund_partial'),
                                     order_id: overrides.fetch(:order_id, '501'), version: overrides.fetch(:version, version),
                                     idempotency_key: idempotency_key, params: params)
    end
  end

  describe '#availability' do
    it 'reads the order now and adds Lynomia\'s rules to the provider\'s capabilities' do
      result = actions_for.call.availability('501')

      expect(provider).to have_received(:action_snapshot).with('501')
      expect(result[:version]).to eq(version)
      expect(result[:order]).not_to have_key('customer')
      expect(result[:actions]).to include(
        'refund_partial' => { available: true, max_amount: '100.00', currency: 'SAR', mode: 'gateway' },
        'cancel_order' => { available: false, reason: 'paid_refund_first' },
        'resend_invoice' => { available: false, reason: 'unsupported' }, 'update_shipping' => { available: false, reason: 'unsupported' }
      )
    end

    it 'tells an agent without the permission why, action by action' do
      result = actions_for.call(agent).availability('501')

      expect(result[:actions].values_at('refund_full', 'update_order_status')).to all(eq(available: false, reason: 'permission_denied'))
    end

    it 'does not find an order that is not the linked customer\'s, and never reads it' do
      allow(provider).to receive(:list_customer_orders).and_return([order.with(external_order_id: '502')])

      expect { actions_for.call.availability('501') }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('NOT_FOUND') }
      expect(provider).not_to have_received(:action_snapshot)
    end

    it 'does not find anything without a link, with a removed link, or for a malformed order id' do
      expect { actions_for.call.availability('501 OR 1=1') }.to raise_error(Commerce::Error, /NOT_FOUND/)

      link.update!(match_source: :suppressed)
      expect { actions_for.call.availability('501') }.to raise_error(Commerce::Error, /NOT_FOUND/)
      expect(provider).not_to have_received(:list_customer_orders)
    end

    it 'reads nothing when the store\'s actions are off, and says why' do
      store.update!(settings: {})
      expect { actions_for.call.availability('501') }.to raise_error(Commerce::Error) { |error|
        expect(error.as_json).to eq(code: 'ACTIONS_DISABLED', reason: 'store_actions_off')
      }

      store.update!(settings: { 'order_actions' => true })
      allow(provider).to receive(:write_access_problem).and_return('read_only_key')
      expect { actions_for.call.availability('501') }.to raise_error(Commerce::Error) { |error|
        expect(error.as_json).to eq(code: 'WRITE_ACCESS_DENIED', reason: 'read_only_key')
      }
      expect(provider).not_to have_received(:list_customer_orders)
    end

    it 'follows the installation kill switch' do
      with_modified_env(COMMERCE_ACTIONS_ENABLED: 'false') do
        expect { actions_for.call.availability('501') }.to raise_error(Commerce::Error, /ACTIONS_DISABLED: actions_disabled/)
      end
    end

    it 'flags a store whose credentials were rejected' do
      allow(provider).to receive(:list_customer_orders).and_raise(Commerce::Error, 'AUTH_INVALID')

      expect { actions_for.call.availability('501') }.to raise_error(Commerce::Error, /AUTH_INVALID/)
      expect(store.reload).to be_needs_reauth
    end
  end

  describe '#request' do
    it 'records the action, audits it and queues it, without writing to the store' do
      run = nil
      expect { run = refund.call }.to have_enqueued_job(Commerce::ActionJob).once

      expect(run).to be_pending
      expect(run).to have_attributes(account_id: account.id, commerce_store_id: store.id, contact_id: contact.id, requested_by: admin,
                                     provider: 'woocommerce', action_type: 'refund_partial', external_resource_id: '501', idempotency_key: key)
      expect(run.metadata).to eq('amount' => '40.00', 'currency' => 'SAR', 'reason' => 'customer_request', 'version' => version)
      expect(provider).not_to have_received(:action_snapshot)
    end

    it 'answers a double submit with the same run and queues it once' do
      first = refund.call
      expect { expect(refund.call).to eq(first) }.not_to have_enqueued_job(Commerce::ActionJob)
      expect(Commerce::ActionRun.count).to eq(1)
    end

    it 'refuses a key replayed for a different request' do
      refund.call

      expect { refund.call(amount: '50.00') }.to raise_error(Commerce::Error, 'IDEMPOTENCY_CONFLICT')
    end

    it 'refuses a second action on the order while one is unresolved, and stops blocking once reconciliation ran out' do
      first = refund.call

      expect { refund.call(idempotency_key: "commerce-action:#{SecureRandom.uuid}") }.to raise_error(Commerce::Error, 'ACTION_IN_PROGRESS')

      first.update!(status: :unknown)
      expect { refund.call(idempotency_key: "commerce-action:#{SecureRandom.uuid}") }.to raise_error(Commerce::Error, 'ACTION_IN_PROGRESS')

      first.update!(metadata: first.metadata.merge('reconcile' => 'exhausted'))
      expect(refund.call(idempotency_key: "commerce-action:#{SecureRandom.uuid}")).to be_pending
    end

    it 'refuses agents without the permission' do
      expect { refund.call(user: agent) }.to raise_error(Pundit::NotAuthorizedError)
      expect(Commerce::ActionRun.count).to eq(0)
    end

    it 'accepts only documented values' do
      invalid = [
        [{ action_type: 'delete_order' }, 'INVALID_REQUEST'], [{ idempotency_key: SecureRandom.uuid }, 'INVALID_REQUEST'],
        [{ idempotency_key: "commerce-recovery:#{SecureRandom.uuid}" }, 'INVALID_REQUEST'], [{ version: 'stale' }, 'INVALID_REQUEST'],
        [{ order_id: '../501' }, 'INVALID_REQUEST'], [{ amount: '-1' }, 'INVALID_AMOUNT'], [{ amount: '0.00' }, 'INVALID_AMOUNT'],
        [{ amount: '1e3' }, 'INVALID_AMOUNT'], [{ amount: 40 }, 'INVALID_AMOUNT'], [{ params: { currency: 'sar' } }, 'INVALID_REQUEST'],
        [{ params: { reason: 'because' } }, 'INVALID_REQUEST']
      ]
      invalid.each do |overrides, code|
        expect { refund.call(**overrides) }.to raise_error(Commerce::Error, code)
      end
      [{ action_type: 'cancel_order', params: { reason: 'other', restock: 'yes' } },
       { action_type: 'update_order_status', params: { target_status: 'trash' } }].each do |overrides|
        expect { refund.call(**overrides) }.to raise_error(Commerce::Error, 'INVALID_REQUEST')
      end
      expect(Commerce::ActionRun.count).to eq(0)
    end

    it 'limits how many actions one agent can request' do
      Commerce::OrderActions::RATE_LIMITS[:user].first.times do |index|
        refund.call(idempotency_key: "commerce-action:#{SecureRandom.uuid}", order_id: (900 + index).to_s)
      end

      expect { refund.call }.to raise_error(Commerce::Error) { |error| expect(error.code).to eq('RATE_LIMITED') }
    end
  end
end
