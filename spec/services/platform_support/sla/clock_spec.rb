require 'rails_helper'
require_relative '../../../requests/platform_support/security/platform_support_contract_stub'

# Calendar-time arithmetic, two clocks, and the pause rule.
#
# THE NUMBERS ARE SYNTHETIC AND DELIBERATELY ABSURD: 60 and 180 seconds. There is no production target value
# in this module, in code, in a seed or in a fixture (D-7).
RSpec.describe PlatformSupport::Sla::Clock do
  let(:synthetic_first_response) { 60 }
  let(:synthetic_resolution) { 180 }
  let(:account) { create(:account) }
  let(:policy) do
    PlatformSupport::SlaPolicy.create!(name: 'Synthetic', first_response_time_threshold: synthetic_first_response,
                                      resolution_time_threshold: synthetic_resolution)
  end
  let(:resolution_only_policy) do
    PlatformSupport::SlaPolicy.create!(name: 'Resolution only', resolution_time_threshold: synthetic_resolution)
  end
  let(:now) { Time.zone.parse('2026-03-05 09:00:00 UTC') }

  def ticket(**attributes)
    PlatformSupportContractStub.ticket!(account: account, **attributes)
  end

  describe '#apply' do
    it 'sets both due times from the moment the policy attached, in calendar seconds' do
      record = ticket(sla_policy: policy)

      described_class.new(record).apply(from: now)

      expect(record.first_response_due_at).to eq(now + synthetic_first_response.seconds)
      expect(record.resolution_due_at).to eq(now + synthetic_resolution.seconds)
    end

    # Calendar time, stated as a property: an overnight window is counted in full, because there is no
    # business-hours calendar in V1 and pretending otherwise would be fake infrastructure.
    it 'counts hours nobody was working' do
      record = ticket(sla_policy: policy)
      thursday_evening = Time.zone.parse('2026-03-05 21:30:00 UTC')

      described_class.new(record).apply(from: thursday_evening)

      expect(record.resolution_due_at).to eq(thursday_evening + synthetic_resolution.seconds)
    end

    # A due time invented backwards from an older created_at is a commitment nobody made.
    it 'measures from the given moment and never from created_at' do
      record = ticket(sla_policy: policy, created_at: now - 1.day)

      described_class.new(record).apply(from: now)

      expect(record.first_response_due_at).to eq(now + synthetic_first_response.seconds)
    end

    # A POLICY WITH NO THRESHOLD PRODUCES NO PROMISE: a nil, never a zero, because a zero reads as "due
    # immediately".
    it 'leaves the first-response due time nil under a resolution-only policy' do
      record = ticket(sla_policy: resolution_only_policy)

      described_class.new(record).apply(from: now)

      expect(record.first_response_due_at).to be_nil
      expect(record.resolution_due_at).to eq(now + synthetic_resolution.seconds)
    end

    it 'promises nothing at all when no policy is attached' do
      record = ticket

      described_class.new(record).apply(from: now)

      expect(record.first_response_due_at).to be_nil
      expect(record.resolution_due_at).to be_nil
    end

    it 'treats a non-positive threshold as no promise' do
      zeroed = PlatformSupport::SlaPolicy.create!(name: 'Zeroed', first_response_time_threshold: 0,
                                                 resolution_time_threshold: synthetic_resolution)
      record = ticket(sla_policy: zeroed)

      described_class.new(record).apply(from: now)

      expect(record.first_response_due_at).to be_nil
    end
  end

  describe 'pause and resume on waiting_on_customer' do
    it 'stops the clock when the ticket moves to waiting_on_customer' do
      record = ticket(sla_policy: policy, status: :waiting_on_customer)
      described_class.new(record).apply(from: now)

      described_class.new(record).sync_pause(at: now + 10.seconds)

      expect(record.sla_paused_at).to eq(now + 10.seconds)
    end

    # The non-obvious half, and it is deliberate: waiting on ourselves is our own delay.
    it 'does not pause on waiting_on_lynomia' do
      record = ticket(sla_policy: policy, status: :waiting_on_lynomia)
      described_class.new(record).apply(from: now)

      described_class.new(record).sync_pause(at: now + 10.seconds)

      expect(record.sla_paused_at).to be_nil
    end

    it 'moves every outstanding due time forward by exactly the paused duration and records the total' do
      record = ticket(sla_policy: policy, status: :waiting_on_customer)
      clock = described_class.new(record)
      clock.apply(from: now)
      clock.pause(at: now + 10.seconds)

      record.status = 'in_progress'
      described_class.new(record).sync_pause(at: now + 35.seconds)

      expect(record.sla_paused_seconds).to eq(25)
      expect(record.first_response_due_at).to eq(now + synthetic_first_response.seconds + 25.seconds)
      expect(record.resolution_due_at).to eq(now + synthetic_resolution.seconds + 25.seconds)
      expect(record.sla_paused_at).to be_nil
    end

    it 'accumulates across two separate pauses rather than replacing the total' do
      record = ticket(sla_policy: policy)
      clock = described_class.new(record)
      clock.apply(from: now)

      clock.pause(at: now + 10.seconds)
      clock.resume(at: now + 20.seconds)
      clock.pause(at: now + 30.seconds)
      clock.resume(at: now + 37.seconds)

      expect(record.sla_paused_seconds).to eq(17)
    end

    it 'is idempotent in both directions' do
      record = ticket(sla_policy: policy)
      clock = described_class.new(record)
      clock.apply(from: now)

      clock.pause(at: now + 10.seconds)
      clock.pause(at: now + 20.seconds)
      expect(record.sla_paused_at).to eq(now + 10.seconds)

      clock.resume(at: now + 30.seconds)
      clock.resume(at: now + 90.seconds)
      expect(record.sla_paused_seconds).to eq(20)
    end

    # An ungoverned ticket has no clock to stop, so pausing it would record a pause that measures nothing.
    it 'does not pause a ticket with no policy' do
      record = ticket(status: :waiting_on_customer)

      described_class.new(record).sync_pause(at: now)

      expect(record.sla_paused_at).to be_nil
    end

    it 'leaves a nil due time nil when resuming' do
      record = ticket(sla_policy: resolution_only_policy)
      clock = described_class.new(record)
      clock.apply(from: now)
      clock.pause(at: now + 5.seconds)

      clock.resume(at: now + 15.seconds)

      expect(record.first_response_due_at).to be_nil
      expect(record.resolution_due_at).to eq(now + synthetic_resolution.seconds + 10.seconds)
    end
  end

  describe '#restart_resolution' do
    it 'gives a new resolution target from the reopen instant and clears the resolution breach' do
      record = ticket(sla_policy: policy, first_responded_at: now, resolution_breached_at: now + 1.minute)
      reopened_at = now + 1.hour

      described_class.new(record).restart_resolution(from: reopened_at)

      expect(record.resolution_due_at).to eq(reopened_at + synthetic_resolution.seconds)
      expect(record.resolution_breached_at).to be_nil
      expect(record.first_responded_at).to eq(now)
    end
  end

  describe '#record_first_response' do
    it 'stamps the response and leaves it met when it landed inside the window' do
      record = ticket(sla_policy: policy)
      described_class.new(record).apply(from: now)

      described_class.new(record).record_first_response(at: now + 30.seconds)

      expect(record.first_responded_at).to eq(now + 30.seconds)
      expect(record.first_response_breached_at).to be_nil
    end

    # Message time against due time, never sweep time.
    it 'stamps a breach at the reply time when the reply was late' do
      record = ticket(sla_policy: policy)
      described_class.new(record).apply(from: now)
      late = now + synthetic_first_response.seconds + 1.second

      described_class.new(record).record_first_response(at: late)

      expect(record.first_response_breached_at).to eq(late)
    end

    it 'decides once and never again' do
      record = ticket(sla_policy: policy)
      described_class.new(record).apply(from: now)
      described_class.new(record).record_first_response(at: now + 30.seconds)

      described_class.new(record).record_first_response(at: now + 1.day)

      expect(record.first_responded_at).to eq(now + 30.seconds)
      expect(record.first_response_breached_at).to be_nil
    end

    it 'records the response without a breach when nothing was promised' do
      record = ticket

      described_class.new(record).record_first_response(at: now)

      expect(record.first_responded_at).to eq(now)
      expect(record.first_response_breached_at).to be_nil
    end
  end

  # The next-response clock is CUT from V1 (§B-6) and so is the 75%-of-window warning (§B-7). Neither has a
  # column or an event type in the frozen contract, so neither can be recorded -- and a clock that cannot be
  # recorded must not exist in code either.
  describe 'what V1 deliberately does not have' do
    it 'exposes no next-response clock and no warning threshold' do
      expect(described_class.instance_methods(false)).not_to include(:next_response_due_at, :warn, :warning_at)
      expect(described_class.constants).to contain_exactly(:PAUSING_STATUSES)
      expect(PlatformSupport::SlaPolicy.column_names).not_to include('next_response_time_threshold')
      expect(PlatformSupport::Ticket.column_names.grep(/next_response/)).to be_empty
    end

    it 'names exactly one pausing status' do
      expect(described_class::PAUSING_STATUSES).to eq(%w[waiting_on_customer])
    end
  end
end
