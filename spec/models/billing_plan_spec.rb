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
end
