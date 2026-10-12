require 'rails_helper'
require_relative '../../../requests/platform_support/security/platform_support_contract_stub'

# Policy resolution is DATA-DRIVEN by `billing_plan_id`, with the single default row (`billing_plan_id IS
# NULL`) as the fallback, and a desk with no rows promises nothing.
#
# EVERY THRESHOLD HERE IS AN OBVIOUSLY SYNTHETIC NUMBER -- 11 and 22 seconds. No production target value
# exists anywhere in this module: the numbers are owner data, entered as policy records (D-7). If a value in
# this file ever starts to look like a plausible support target, somebody has put owner data into code.
RSpec.describe PlatformSupport::Sla::PolicyResolver do
  let(:synthetic_first_response) { 11 }
  let(:synthetic_resolution) { 22 }
  let(:plan) { create(:billing_plan) }
  let(:other_plan) { create(:billing_plan) }
  let(:account) { create(:account) }

  def policy(billing_plan_id:, active: true, name: 'Synthetic')
    PlatformSupport::SlaPolicy.create!(
      name: name, billing_plan_id: billing_plan_id, active: active,
      first_response_time_threshold: synthetic_first_response, resolution_time_threshold: synthetic_resolution
    )
  end

  it 'resolves the policy whose billing_plan_id matches the account plan' do
    matching = policy(billing_plan_id: plan.id, name: 'For this plan')
    policy(billing_plan_id: other_plan.id, name: 'For another plan')
    policy(billing_plan_id: nil, name: 'Installation default')
    create(:billing_subscription, account: account, plan: plan)

    expect(described_class.for(account: account)).to eq(matching)
  end

  it 'falls back to the single default row when the plan has none' do
    default = policy(billing_plan_id: nil, name: 'Installation default')
    policy(billing_plan_id: other_plan.id, name: 'For another plan')
    create(:billing_subscription, account: account, plan: plan)

    expect(described_class.for(account: account)).to eq(default)
  end

  it 'falls back to the default row for an account with no subscription at all' do
    default = policy(billing_plan_id: nil, name: 'Installation default')

    expect(described_class.for(account: account)).to eq(default)
  end

  # The whole point of keying on the id. `billing_plans` has no tier and no code column and `name` is free
  # text an operator edits in Super Admin, so a rename must not change which policy applies.
  it 'keeps matching after the plan is renamed' do
    matching = policy(billing_plan_id: plan.id)
    create(:billing_subscription, account: account, plan: plan)
    plan.update!(name: 'A completely different plan name')

    expect(described_class.for(account: account.reload)).to eq(matching)
  end

  it 'ignores an inactive policy and falls through to the default' do
    policy(billing_plan_id: plan.id, active: false)
    default = policy(billing_plan_id: nil, name: 'Installation default')
    create(:billing_subscription, account: account, plan: plan)

    expect(described_class.for(account: account)).to eq(default)
  end

  it 'ignores an inactive default row and resolves nothing' do
    policy(billing_plan_id: nil, active: false)

    expect(described_class.for(account: account)).to be_nil
  end

  # NO POLICY ROW IS SEEDED ANYWHERE, so this is the state a freshly deployed installation is in until the
  # owner enters their targets.
  it 'resolves nothing when no policy rows exist' do
    expect(PlatformSupport::SlaPolicy.count).to eq(0)
    expect(described_class.for(account: account)).to be_nil
  end

  it 'resolves nothing for a nil account' do
    policy(billing_plan_id: nil)

    expect(described_class.for(account: nil)).to be_nil
  end

  # The honesty rule M2 enforces: a policy with neither target cannot be created, so "a policy with no
  # threshold" can only ever mean a policy that set one of the two.
  it 'cannot store a policy with neither threshold' do
    record = PlatformSupport::SlaPolicy.new(name: 'Empty', billing_plan_id: nil)

    expect(record).not_to be_valid
  end
end
