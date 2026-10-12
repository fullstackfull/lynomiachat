require 'rails_helper'

RSpec.describe Operations::IncidentTimeline do
  let(:account) { create(:account) }
  let(:operator) { create(:super_admin) }
  let(:signal) do
    Operations::Signal.create!(source: 'queue', signal: 'backlog', severity: 'warning', reason: 'The default queue is behind',
                               first_seen_at: 3.hours.ago, last_seen_at: 10.minutes.ago, occurrences: 42)
  end

  def types = described_class.new(signal).call.map(&:event_type)

  # Derived from the signal's own columns, not stored again. Storing a `recurred` row per observation would
  # write 1,440 rows a day for a channel failing every minute to say what `occurrences` already says.
  it 'derives detection and recurrence from the signal itself' do
    entries = described_class.new(signal).call

    expect(entries.map(&:event_type)).to eq(%w[detected recurred])
    expect(entries.first.at).to be_within(1.second).of(signal.first_seen_at)
    expect(entries.last.detail['occurrences']).to eq(42)
    expect(entries).to all(be_machine)
  end

  it 'does not claim a recurrence for a problem seen once' do
    signal.update!(occurrences: 1, last_seen_at: signal.first_seen_at)

    expect(types).to eq(%w[detected])
  end

  it 'adds the recovery once something observed the thing working again' do
    signal.update!(resolved_at: 1.minute.ago)

    expect(types).to eq(%w[detected recurred resolved])
  end

  describe 'with operator decisions' do
    before do
      lifecycle = Operations::SignalLifecycle.new(signal: signal, actor: operator)
      lifecycle.acknowledge(reason: 'looking at it')
      lifecycle.suppress(until_time: 2.hours.from_now, reason: 'known and noisy')
    end

    it 'merges them in order and marks them as human, not observed' do
      entries = described_class.new(signal.reload).call

      expect(entries.map(&:event_type)).to eq(%w[detected recurred acknowledged suppressed])
      expect(entries.select(&:machine?).map(&:event_type)).to eq(%w[detected recurred])
      expect(entries.last.actor_name).to eq(operator.available_name)
      expect(entries.last.reason).to eq('known and noisy')
    end

    # An acknowledgement stamped in the same second as a recurrence happened AFTER it.
    it 'puts the observation before the human reaction when they share a timestamp' do
      moment = Time.current
      signal.update!(last_seen_at: moment)
      signal.events.update_all(created_at: moment) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.new(signal.reload).call.map(&:event_type).first(2)).to eq(%w[detected recurred])
    end
  end

  it 'records a support case on the timeline, with the operator who opened it' do
    ticket = create(:support_ticket, account: account)
    Operations::SignalLifecycle.new(signal: signal, actor: operator).record_case(ticket)

    entry = described_class.new(signal.reload).call.last

    expect(entry.event_type).to eq('case_created')
    expect(entry.detail['support_ticket_reference']).to eq(ticket.reference)
    expect(entry).not_to be_machine
  end
end
