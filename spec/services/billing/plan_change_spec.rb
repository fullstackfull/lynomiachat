require 'rails_helper'

RSpec.describe Billing::PlanChange do
  let(:account) { create(:account) }
  let(:current_plan) { create(:billing_plan, stripe_price_id: 'price_starter') }
  let(:target_plan) { create(:billing_plan, stripe_price_id: 'price_pro') }

  before do
    allow(Billing::Settings).to receive_messages(stripe_configured?: true, stripe_secret_key: 'sk_test_fake')
    # Stubbing the keys turns commercial enforcement on, which gives the account a subscription of its own,
    # so take that row rather than creating a second one.
    Billing::TrialStarter.subscription_for(account).update!(
      plan: current_plan, status: 'active', source: 'stripe', stripe_subscription_id: 'sub_1',
      stripe_customer_id: 'cus_1', trial_ends_at: nil
    )
  end

  # P11.16. `proration_date` decides how much of the period Stripe prorates, so a browser that chooses it
  # chooses what it pays. Only a timestamp this server minted, and only while the quote is fresh, is accepted.
  describe 'the proration timestamp the client sends back' do
    subject(:change) { described_class.new(account: account, plan: target_plan) }

    it 'refuses a timestamp in the future, and calls Stripe not at all' do
      allow(Stripe::Subscription).to receive(:update)

      expect { change.perform(proration_date: 2.days.from_now.to_i) }
        .to raise_error(described_class::Error, /no longer valid/)
      expect(Stripe::Subscription).not_to have_received(:update)
    end

    it 'refuses a quote older than the validity window' do
      expect { change.perform(proration_date: (described_class::QUOTE_VALIDITY + 1.minute).ago.to_i) }
        .to raise_error(described_class::Error, /no longer valid/)
    end

    it 'prices the change at the fresh timestamp the preview returned' do
      quoted_at = 2.minutes.ago.to_i
      # Stripe's own constructor, so the object graph is the gem's rather than a double's invented contract.
      allow(Stripe::Subscription).to receive(:retrieve)
        .and_return(Stripe::Subscription.construct_from(id: 'sub_1', items: { data: [{ id: 'si_1' }] }))
      allow(Stripe::Subscription).to receive(:update)
        .and_return(Stripe::Subscription.construct_from(id: 'sub_1', pending_update: nil))
      allow(Billing::SubscriptionSync).to receive(:new).and_return(instance_double(Billing::SubscriptionSync, perform: true))

      change.perform(proration_date: quoted_at)

      expect(Stripe::Subscription).to have_received(:update)
        .with('sub_1', hash_including(proration_date: quoted_at), hash_including(:api_key))
    end
  end
end
