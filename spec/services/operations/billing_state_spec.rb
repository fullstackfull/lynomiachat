require 'rails_helper'

RSpec.describe Operations::BillingState do
  let(:account) { create(:account) }
  let(:plan) { create(:billing_plan) }

  # The distinction the whole block exists to draw. A declined card is a commercial fact Stripe already told
  # the customer about; nobody should be woken for it.
  it 'counts a past-due subscription commercially and does not make it an incident' do
    BillingSubscription.create!(account: account, plan: plan, status: 'past_due', source: 'stripe',
                                grace_period_ends_at: 3.days.from_now)

    state = described_class.new.call

    expect(state[:commercial][:past_due]).to eq(1)
    expect(state[:commercial][:by_status]['past_due']).to eq(1)
    expect(state[:incidents][:open]).to be_zero
  end

  it 'reports the installation failing at its own billing job as an incident' do
    Billing::OperationsSignal.record_unknown_customer(event_type: 'customer.subscription.updated')

    state = described_class.new.call

    expect(state[:incidents][:open]).to eq(1)
    expect(state[:incidents][:by_signal]).to eq({ 'unknown_provider_customer' => 1 })
  end

  it 'reports every declared status, including the ones with no subscriptions' do
    expect(described_class.new.call[:commercial][:by_status].keys).to eq(BillingSubscription::STATUSES)
  end

  it 'counts the trials about to end, which is a conversation and not a fault' do
    BillingSubscription.create!(account: account, plan: plan, status: 'trialing', source: 'manual',
                                trial_ends_at: 3.days.from_now)

    expect(described_class.new.call[:commercial][:trials_ending]).to eq(1)
  end

  # A recent list, never a total: whether an account is locked is the subscription model's time-and-config
  # judgement, not a column this page can count.
  it 'lists the accounts the product has actually stopped working for, and says how far it looked' do
    locked = BillingSubscription.create!(account: account, plan: plan, status: 'canceled', source: 'stripe')

    state = described_class.new.call

    expect(state[:locked][:recent].map { |row| row[:account].id }).to eq([locked.account_id])
    expect(state[:locked][:candidates_read]).to eq(1)
  end
end
