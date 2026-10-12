require 'rails_helper'

RSpec.describe Commerce::StoreHealth do
  include_context 'with commerce encryption'

  let(:store) { create(:commerce_store) }
  let(:health) { described_class.create!(commerce_store_id: store.id) }

  describe '#api_state' do
    # The console's standing rule. A store nobody has called is not fine, it is unobserved.
    it 'is unknown when nothing has ever been recorded' do
      expect(health.api_state).to eq('unknown')
      expect(health.health_status).to eq(Operations::Health::UNKNOWN)
    end

    it 'is healthy inside the freshness window' do
      health.update!(last_api_success_at: 1.hour.ago)

      expect(health.api_state).to eq('healthy')
      expect(health.health_status).to eq(Operations::Health::HEALTHY)
    end

    # Stale is NOT a fault: a store is only called when something asks it something, so a quiet store
    # legitimately goes a long time with nothing to report. It maps to unknown, never to red.
    it 'is stale, and reads as unknown, once the last success is outside the window' do
      health.update!(last_api_success_at: (described_class::STALE_AFTER + 1.hour).ago)

      expect(health.api_state).to eq('stale')
      expect(health.health_status).to eq(Operations::Health::UNKNOWN)
    end

    it 'is failing while the last outcome was a failure, however recent the last success' do
      health.update!(last_api_success_at: 1.minute.ago, consecutive_failures: 1)

      expect(health.api_state).to eq('failing')
      expect(health.health_status).to eq(Operations::Health::WARNING)
    end

    it 'escalates to critical once failures repeat' do
      health.update!(consecutive_failures: 3)

      expect(health.health_status).to eq(Operations::Health::CRITICAL)
    end
  end

  describe '#webhook_state' do
    it 'says none, not unhealthy, before the first delivery' do
      expect(health.webhook_state).to eq('none')
    end

    # Driven by the provider contract itself (Commerce::Providers::Base.supports_realtime?) rather than by a
    # second list here that could disagree with it.
    it 'says unsupported for a provider with no webhooks Lynomia consumes' do
      allow(Commerce::Providers::Woocommerce).to receive(:supports_realtime?).and_return(false)

      expect(health.webhook_state).to eq('unsupported')
    end
  end
end
