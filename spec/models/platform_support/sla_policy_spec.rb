require 'rails_helper'

RSpec.describe PlatformSupport::SlaPolicy do
  let(:plan) { create(:billing_plan) }

  # Obviously synthetic numbers. No production target value appears anywhere in this module's code or specs:
  # thresholds are operator-entered data, which is the whole point of keeping them on a row.
  let(:synthetic_first_response) { 111 }
  let(:synthetic_resolution) { 2222 }

  it 'has no next-response threshold, because nothing in the schema could measure one' do
    expect(described_class.column_names).not_to include('next_response_time_threshold')
  end

  it 'stores thresholds as integer seconds rather than the tenant table floats' do
    expect(described_class.columns_hash['first_response_time_threshold'].type).to eq(:integer)
    expect(described_class.columns_hash['resolution_time_threshold'].type).to eq(:integer)
  end

  it 'refuses a policy with no target at all, which would make a ticket look governed when it is not' do
    policy = described_class.new(name: 'Empty')
    expect(policy).not_to be_valid
    expect(policy.errors[:base]).to be_present
  end

  it 'accepts a policy with either target alone' do
    expect(described_class.create!(name: 'First response only', billing_plan: plan,
                                   first_response_time_threshold: synthetic_first_response)).to be_persisted
  end

  it 'refuses a non-positive or absurd threshold' do
    expect(described_class.new(name: 'Zero', resolution_time_threshold: 0)).not_to be_valid
    expect(described_class.new(name: 'Forever', resolution_time_threshold: 366.days.to_i)).not_to be_valid
  end

  describe 'the mapping key' do
    it 'is the plan id, and a plan may have only one policy' do
      described_class.create!(name: 'Plan policy', billing_plan: plan,
                              resolution_time_threshold: synthetic_resolution)

      expect do
        described_class.create!(name: 'Second policy for the same plan', billing_plan: plan,
                                resolution_time_threshold: synthetic_resolution)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows exactly one installation default, which a plain unique index would not enforce' do
      described_class.create!(name: 'Installation default', resolution_time_threshold: synthetic_resolution)

      expect do
        described_class.create!(name: 'A second default', resolution_time_threshold: synthetic_resolution)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'finds the default row through its own scope' do
      default = described_class.create!(name: 'Installation default',
                                        resolution_time_threshold: synthetic_resolution)
      described_class.create!(name: 'Plan policy', billing_plan: plan,
                              resolution_time_threshold: synthetic_resolution)

      expect(described_class.installation_default).to eq([default])
    end
  end

  it 'nullifies on a ticket rather than taking it down when the policy goes' do
    account = create(:account)
    policy = described_class.create!(name: 'Plan policy', billing_plan: plan,
                                     resolution_time_threshold: synthetic_resolution)
    ticket = PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                             reporter_name: 'Reporter', subject: 'Something',
                                             sla_policy: policy)

    policy.destroy!

    expect(ticket.reload).to have_attributes(sla_policy_id: nil)
  end

  it 'seeds no rows: a desk with no policy promises nothing, which is the correct starting state' do
    expect(described_class.count).to eq(0)
  end
end
