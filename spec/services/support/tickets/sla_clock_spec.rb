require 'rails_helper'

RSpec.describe Support::Tickets::SlaClock do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:policy) do
    create(:support_sla_policy, account: account, first_response_time_threshold: 2.hours.to_i,
                                resolution_time_threshold: 8.hours.to_i)
  end

  describe 'calendar time' do
    it 'measures both targets from the moment the policy is attached, not from created_at' do
      ticket = create(:support_ticket, account: account, created_at: 5.days.ago)
      ticket.sla_policy = policy
      now = Time.zone.parse('2026-10-09 10:00:00 UTC')

      described_class.new(ticket).apply(from: now)

      expect(ticket.first_response_due_at).to eq(now + 2.hours)
      expect(ticket.resolution_due_at).to eq(now + 8.hours)
    end

    it 'leaves a target nil when the policy does not set it' do
      only_resolution = create(:support_sla_policy, account: account, first_response_time_threshold: nil,
                                                    resolution_time_threshold: 4.hours.to_i)
      ticket = create(:support_ticket, account: account, sla_policy: only_resolution)

      described_class.new(ticket).apply

      expect(ticket.first_response_due_at).to be_nil
      expect(ticket.resolution_due_at).not_to be_nil
    end

    it 'does nothing at all without a policy' do
      ticket = create(:support_ticket, account: account)

      described_class.new(ticket).apply

      expect(ticket.resolution_due_at).to be_nil
    end
  end

  describe 'business hours' do
    let(:business_policy) do
      create(:support_sla_policy, account: account, first_response_time_threshold: 4.hours.to_i,
                                  resolution_time_threshold: nil, only_during_business_hours: true)
    end

    before do
      inbox.update!(working_hours_enabled: true, timezone: 'UTC')
      (1..5).each { |day| create(:working_hour, inbox: inbox, day_of_week: day, open_hour: 9, close_hour: 17) }
    end

    it 'pushes a target past the close of business into the next working day' do
      ticket = create(:support_ticket, account: account, inbox: inbox, sla_policy: business_policy)
      # Monday 15:00 UTC. Two hours remain today, so the other two land on Tuesday morning.
      from = Time.zone.parse('2026-10-05 15:00:00 UTC')

      described_class.new(ticket).apply(from: from)

      expect(ticket.first_response_due_at).to eq(Time.zone.parse('2026-10-06 11:00:00 UTC'))
    end

    it 'is applicable only when the policy asks, the case has an inbox, and that inbox has hours' do
      with_inbox = create(:support_ticket, account: account, inbox: inbox, sla_policy: business_policy)
      expect(described_class.new(with_inbox).business_hours_applicable?).to be(true)

      # The decisive limitation: business hours are inbox-scoped because WorkingHours::Config is built from the
      # inbox, so an internal case with no inbox cannot have them.
      no_inbox = create(:support_ticket, account: account, sla_policy: business_policy)
      expect(described_class.new(no_inbox).business_hours_applicable?).to be(false)

      hours_off = create(:inbox, account: account, working_hours_enabled: false)
      off = create(:support_ticket, account: account, inbox: hours_off, sla_policy: business_policy)
      expect(described_class.new(off).business_hours_applicable?).to be(false)
    end

    it 'falls back to calendar time for a case with no inbox even under a business-hours policy' do
      ticket = create(:support_ticket, account: account, sla_policy: business_policy)
      from = Time.zone.parse('2026-10-05 15:00:00 UTC')

      described_class.new(ticket).apply(from: from)

      expect(ticket.first_response_due_at).to eq(from + 4.hours)
    end
  end

  describe 'pause and resume' do
    let(:ticket) { create(:support_ticket, account: account, sla_policy: policy) }

    before { described_class.new(ticket).apply(from: Time.zone.parse('2026-10-09 10:00:00 UTC')) }

    it 'moves both due times forward by exactly the time the clock was stopped' do
      clock = described_class.new(ticket)
      first_due = ticket.first_response_due_at
      resolution_due = ticket.resolution_due_at

      clock.pause(at: Time.zone.parse('2026-10-09 11:00:00 UTC'))
      clock.resume(at: Time.zone.parse('2026-10-09 12:30:00 UTC'))

      expect(ticket.sla_paused_seconds).to eq(90.minutes.to_i)
      expect(ticket.first_response_due_at).to eq(first_due + 90.minutes)
      expect(ticket.resolution_due_at).to eq(resolution_due + 90.minutes)
      expect(ticket.sla_paused_at).to be_nil
    end

    it 'accumulates across several pauses' do
      clock = described_class.new(ticket)
      clock.pause(at: Time.zone.parse('2026-10-09 11:00:00 UTC'))
      clock.resume(at: Time.zone.parse('2026-10-09 11:30:00 UTC'))
      clock.pause(at: Time.zone.parse('2026-10-09 13:00:00 UTC'))
      clock.resume(at: Time.zone.parse('2026-10-09 13:15:00 UTC'))

      expect(ticket.sla_paused_seconds).to eq(45.minutes.to_i)
    end

    it 'ignores a resume with no pause, and a second pause while already paused' do
      clock = described_class.new(ticket)
      clock.resume
      expect(ticket.sla_paused_seconds).to eq(0)

      clock.pause(at: Time.zone.parse('2026-10-09 11:00:00 UTC'))
      clock.pause(at: Time.zone.parse('2026-10-09 12:00:00 UTC'))
      expect(ticket.sla_paused_at).to eq(Time.zone.parse('2026-10-09 11:00:00 UTC'))
    end

    it 'does not start a clock on a case with no policy' do
      without = create(:support_ticket, account: account)
      described_class.new(without).pause

      expect(without.sla_paused_at).to be_nil
    end
  end

  describe 'restart_resolution' do
    it 'gives a new resolution target and clears a previous breach' do
      ticket = create(:support_ticket, account: account, sla_policy: policy,
                                       resolution_breached_at: 2.days.ago, resolution_due_at: 3.days.ago)
      now = Time.zone.parse('2026-10-09 10:00:00 UTC')

      described_class.new(ticket).restart_resolution(from: now)

      expect(ticket.resolution_due_at).to eq(now + 8.hours)
      expect(ticket.resolution_breached_at).to be_nil
    end
  end
end
