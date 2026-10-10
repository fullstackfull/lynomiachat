require 'rails_helper'

RSpec.describe BillingPlan do
  it 'keeps a stores limit next to agents and inboxes, empty meaning unlimited' do
    plan = described_class.create!(name: 'Commerce', limits: { 'agents' => '5', 'inboxes' => '', 'stores' => '2', 'other' => '9' })

    expect(plan.limits).to eq('agents' => 5, 'stores' => 2)
    expect(plan.limit_for(:stores)).to eq(2)
    expect(plan.limit_for(:inboxes)).to be_nil
  end

  it 'refuses a negative stores limit' do
    expect(described_class.new(name: 'Commerce', limits: { 'stores' => '-1' })).not_to be_valid
  end

  # P-FINAL: a plan with billed subscribers may be widened but not narrowed, because a narrowing takes away
  # mid-period something a customer is paying for. Create a new plan and move them instead.
  describe 'narrowing a plan people are billed on' do
    let(:plan) do
      create(:billing_plan, limits: { 'agents' => 5 }, features: ['lynomia_commerce'],
                            channel_entitlements: ['Channel::Api', 'Channel::Whatsapp'])
    end

    def billed!(status = 'active')
      create(:billing_subscription, plan: plan, status: status)
    end

    it 'refuses to withdraw a feature' do
      billed!
      plan.features = []

      expect(plan).not_to be_valid
      expect(plan.errors.full_messages.to_sentence).to include('the feature lynomia_commerce')
    end

    it 'refuses to lower a ceiling, and names what it would cost' do
      billed!('trialing')
      plan.limits = { 'agents' => 2 }

      expect(plan).not_to be_valid
      expect(plan.errors.full_messages.to_sentence).to include('the agents ceiling, from 5 to 2')
        .and include('1 account is billed')
    end

    it 'refuses a ceiling where there was none' do
      billed!
      plan.limits = { 'agents' => 5, 'inboxes' => 3 }

      expect(plan).not_to be_valid
      expect(plan.errors.full_messages.to_sentence).to include('a ceiling of 3 on inboxes where there was none')
    end

    it 'refuses to withdraw a channel' do
      billed!('past_due')
      plan.channel_entitlements = ['Channel::Api']

      expect(plan).not_to be_valid
      expect(plan.errors.full_messages.to_sentence).to include('the channel Channel::Whatsapp')
    end

    # An empty list sells every channel, so filling it in for the first time withdraws everything it omits.
    it 'refuses a first channel list on a plan that sold them all' do
      open_plan = create(:billing_plan)
      create(:billing_subscription, plan: open_plan, status: 'active')
      open_plan.channel_entitlements = ['Channel::Api']

      expect(open_plan).not_to be_valid
      expect(open_plan.errors.full_messages.to_sentence).to include('every channel the new list leaves out')
    end

    it 'allows every widening' do
      billed!
      plan.update!(limits: { 'agents' => 50 }, features: %w[lynomia_commerce lynomia_flow_builder],
                   channel_entitlements: ['Channel::Api', 'Channel::Whatsapp', 'Channel::Email'])

      expect(plan.reload.limit_for(:agents)).to eq(50)
    end

    it 'allows removing a ceiling, which means unlimited' do
      billed!
      plan.update!(limits: {})

      expect(plan.reload.limit_for(:agents)).to be_nil
    end

    it 'allows clearing the channel list, which sells every channel' do
      billed!
      plan.update!(channel_entitlements: [])

      expect(plan.reload.channel_included?('Channel::Email')).to be(true)
    end

    it 'allows a narrowing when nobody is billed on the plan' do
      create(:billing_subscription, plan: plan, status: 'canceled')
      plan.update!(limits: { 'agents' => 1 }, features: [], channel_entitlements: ['Channel::Api'])

      expect(plan.reload.limit_for(:agents)).to eq(1)
    end

    it 'allows an edit that does not touch what the plan sells' do
      billed!
      plan.update!(description: 'Nicer copy', price: 25)

      expect(plan.reload.description).to eq('Nicer copy')
    end
  end
end
