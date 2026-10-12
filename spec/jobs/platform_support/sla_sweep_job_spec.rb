require 'rails_helper'
require_relative '../../requests/platform_support/security/platform_support_contract_stub'

RSpec.describe PlatformSupport::SlaSweepJob do
  let(:account) { create(:account) }
  let(:policy) do
    PlatformSupport::SlaPolicy.create!(name: 'Synthetic', first_response_time_threshold: 60,
                                       resolution_time_threshold: 180)
  end

  it 'runs on the housekeeping queue' do
    expect(described_class.new.queue_name).to eq('housekeeping')
  end

  it 'stamps the breaches the sweep decided' do
    record = PlatformSupportContractStub.ticket!(account: account, sla_policy: policy,
                                                 resolution_due_at: 1.hour.ago)

    described_class.perform_now

    expect(record.reload.resolution_breached_at).to be_present
  end

  # A quiet sweep says nothing: an operator log line per empty run would bury the ones that matter.
  it 'logs nothing when it decided nothing' do
    PlatformSupportContractStub.ticket!(account: account, sla_policy: policy, resolution_due_at: 1.hour.from_now)

    expect(Lynomia::OperatorLog).not_to receive(:info)

    described_class.perform_now
  end

  it 'logs one line naming what it decided' do
    PlatformSupportContractStub.ticket!(account: account, sla_policy: policy, resolution_due_at: 1.hour.ago)

    expect(Lynomia::OperatorLog).to receive(:info)
      .with('PLATFORM_SUPPORT_SLA_SWEEP', first_response_breached: 0, resolution_breached: 1)

    described_class.perform_now
  end
end
