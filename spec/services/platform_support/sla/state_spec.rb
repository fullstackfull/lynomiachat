require 'rails_helper'
require_relative '../../../requests/platform_support/security/platform_support_contract_stub'

# The object both surfaces read to decide whether to show a target at all, so that "no target was set" is
# never rendered as a zero, a dash, or a number nobody committed to.
RSpec.describe PlatformSupport::Sla::State do
  let(:account) { create(:account) }
  let(:policy) do
    PlatformSupport::SlaPolicy.create!(name: 'Synthetic', first_response_time_threshold: 60,
                                       resolution_time_threshold: 180)
  end
  let(:resolution_only_policy) do
    PlatformSupport::SlaPolicy.create!(name: 'Resolution only', resolution_time_threshold: 180)
  end
  let(:now) { Time.zone.parse('2026-03-05 09:00:00 UTC') }

  def ticket(**attributes)
    PlatformSupportContractStub.ticket!(account: account, **attributes)
  end

  # THE SURFACE SAYS SO. This false is what the staff desk turns into "No SLA policy applies" and what the
  # tenant surface turns into no target at all.
  it 'is ungoverned when no policy is attached' do
    expect(described_class.new(ticket)).not_to be_governed
  end

  it 'is ungoverned when a policy is attached but set no due time on this ticket' do
    record = ticket(sla_policy: policy)

    expect(described_class.new(record)).not_to be_governed
  end

  it 'is governed once the clock has set a due time' do
    record = ticket(sla_policy: policy)
    PlatformSupport::Sla::Clock.new(record).apply(from: now)

    expect(described_class.new(record)).to be_governed
  end

  # A resolution-only policy is governed, and still promises nothing on the first-response clock. Reading the
  # column alone cannot tell those apart, which is why this object exists.
  it 'separates the two promises under a resolution-only policy' do
    record = ticket(sla_policy: resolution_only_policy)
    PlatformSupport::Sla::Clock.new(record).apply(from: now)
    state = described_class.new(record)

    expect(state).to be_governed
    expect(state).not_to be_first_response_promised
    expect(state).to be_resolution_promised
  end

  it 'reports a stamped breach and a pause' do
    record = ticket(sla_policy: policy, first_response_breached_at: now, resolution_breached_at: now,
                    sla_paused_at: now)
    state = described_class.new(record)

    expect(state).to be_first_response_breached
    expect(state).to be_resolution_breached
    expect(state).to be_paused
  end

  # Labelled as calendar time on both surfaces, because there is no business-hours path to be in in V1.
  it 'is calendar time' do
    expect(described_class.new(ticket)).to be_calendar_time
  end
end
