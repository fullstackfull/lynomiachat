require 'rails_helper'

RSpec.describe Billing::TrialStarter do
  let(:account) { create(:account) }
  let(:plan) { create(:billing_plan) }

  describe 'with nothing configured' do
    it 'gives an account no subscription, so nothing can lock it' do
      expect(described_class.subscription_for(account)).to be_nil
      expect(account.reload.billing_subscription).to be_nil
    end
  end

  describe 'with a trial configured' do
    before do
      Billing::Settings.update!(trial_enabled: true, trial_days: 14, trial_plan_id: plan.id, trial_once_per_user: false)
    end

    it 'starts the trial on first access' do
      subscription = described_class.subscription_for(account)

      expect(subscription).to have_attributes(status: 'trialing', plan_id: plan.id)
      expect(subscription.trial_ends_at).to be_within(1.minute).of(14.days.from_now)
    end

    # The rollout case. The dashboard's first page fires several parallel account-scoped GETs; each one runs
    # the access guard, each reads no subscription, and each then tries to create one. Only RecordNotUnique
    # was rescued, but `validates :account_id, uniqueness: true` fires before the index does -- so the losers
    # raised RecordInvalid and the browser got 422 "Account has already been taken" on an ordinary GET.
    it 'returns the winner\'s subscription instead of raising when a parallel request got there first' do
      stale = Account.find(account.id)
      stale.billing_subscription # caches nil, as a request that read before the winner committed would have
      winner = described_class.subscription_for(account)

      result = nil
      expect { result = described_class.new(stale).perform }.not_to raise_error
      expect(result.id).to eq(winner.id)
      expect(BillingSubscription.where(account_id: account.id).count).to eq(1)
    end

    # The `trial_once_per_user` rule is deliberately NOT covered here. It reads `account.administrators` at the
    # moment the trial starts, and `Account.after_create_commit :start_billing_trial` fires while the factory's
    # account still has none -- so a factory-built account always gets a trial whatever the rule says. The real
    # signup flow links the administrator inside the same transaction (custom/app/models/custom/account.rb:17),
    # which the factory does not reproduce, and a spec that reordered it would assert an ordering production
    # never has. It is a row in docs/p11/08-uat-runbook.md instead.
  end
end
