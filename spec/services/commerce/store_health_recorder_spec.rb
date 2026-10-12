require 'rails_helper'

# The write strategy and the no-secrets rule, which are the two things this class exists to own
# (docs/product-refinement/09-commerce-operations.md §writer).
RSpec.describe Commerce::StoreHealthRecorder do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, account: account) }

  def health = Commerce::StoreHealth.find_by(commerce_store_id: store.id)

  describe 'recording a provider answer' do
    it 'creates the one snapshot row and stamps the success' do
      described_class.api_success(store)

      expect(Commerce::StoreHealth.where(commerce_store_id: store.id).count).to eq(1)
      expect(health.last_api_success_at).to be_present
      expect(health.consecutive_failures).to be_zero
    end

    # The whole point of the throttle: a store answering every second must not write every second.
    it 'does not write again inside the throttle window' do
      described_class.api_success(store, at: 1.minute.ago)
      first = health.last_api_success_at

      described_class.api_success(store)

      expect(health.reload.last_api_success_at).to be_within(1.second).of(first)
    end

    it 'writes again once the throttle window has passed' do
      described_class.api_success(store, at: (described_class::SUCCESS_THROTTLE + 1.minute).ago)

      described_class.api_success(store)

      expect(health.last_api_success_at).to be_within(5.seconds).of(Time.current)
    end

    # A recovery must be visible at once, throttle or no throttle, and the failure count must go back to zero.
    it 'records a recovery immediately and clears the failure count' do
      described_class.api_failure(store, Commerce::Error.new('STORE_UNAVAILABLE', reason: 'dns'))
      described_class.api_success(store)

      expect(health.consecutive_failures).to be_zero
      expect(health.last_api_success_at).to be_present
      expect(health.api_state).to eq('healthy')
    end
  end

  describe 'recording a provider failure' do
    it 'is written immediately and counts consecutive failures' do
      3.times { described_class.api_failure(store, Commerce::Error.new('TIMEOUT')) }

      expect(health.consecutive_failures).to eq(3)
      expect(health.last_error_code).to eq('TIMEOUT')
      expect(health.api_state).to eq('failing')
    end

    it 'keeps the classified code and the classified reason, and nothing else' do
      described_class.api_failure(store, Commerce::Error.new('INVALID_STORE_URL', reason: 'private_address'))

      expect(health.last_error_code).to eq('INVALID_STORE_URL')
      expect(health.last_error_reason).to eq('private_address')
    end

    # Rule 8: only a classified reason. A Commerce::Error is the only input, so its code is already validated
    # against Commerce::Error::CODES -- but a reason that is not one of ours is dropped rather than stored.
    it 'drops a reason that is not one of the product\'s own identifiers' do
      described_class.api_failure(store, Commerce::Error.new('AUTH_INVALID', reason: 'Bearer sk_live_51H8x: rejected by provider'))

      expect(health.last_error_code).to eq('AUTH_INVALID')
      expect(health.last_error_reason).to be_nil
    end
  end

  describe 'webhooks' do
    it 'stamps an authenticated receipt and, separately, the moment it was applied' do
      described_class.webhook_received(store)
      expect(health.last_webhook_received_at).to be_present
      expect(health.last_webhook_processed_at).to be_nil
      expect(health.webhook_state).to eq('received')

      described_class.webhook_processed(store)
      expect(health.reload.webhook_state).to eq('processed')
    end

    it 'throttles receipts, so one event per order does not mean one write per order' do
      described_class.webhook_received(store, at: 1.minute.ago)
      first = health.last_webhook_received_at

      described_class.webhook_received(store)

      expect(health.reload.last_webhook_received_at).to be_within(1.second).of(first)
    end
  end

  describe 'what it refuses to do' do
    it 'records nothing for a store that does not exist' do
      expect { described_class.api_success(nil) }.not_to change(Commerce::StoreHealth, :count)
    end

    it 'records nothing for a store that has not been saved' do
      expect { described_class.api_success(Commerce::Store.new) }.not_to change(Commerce::StoreHealth, :count)
    end

    # Observability sits inside the conversation panel's provider reads. A bug here must not break the panel.
    it 'never raises into its caller' do
      allow(Commerce::StoreHealth).to receive(:exists?).and_raise(ActiveRecord::StatementInvalid, 'boom')

      expect { described_class.api_success(store) }.not_to raise_error
    end
  end
end
