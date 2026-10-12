require 'rails_helper'

# The operator-handling layer on an operational signal
# (docs/product-refinement/07-operations-control-center-v2.md §4).
#
# What is asserted here is the brief's own list for a Super Admin mutation: explicit typed input, idempotency,
# an audit trail carrying the real operator, and no secret anywhere.
RSpec.describe Operations::SignalLifecycle do
  subject(:lifecycle) { described_class.new(signal: signal, actor: operator) }

  let(:operator) { create(:super_admin, name: 'Hisham Operator') }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:signal) do
    Operations::SignalRecorder.new(source: :email_channel, account: account, subject: inbox)
                              .record(:authentication_failed, severity: :critical, reason: 'IMAP LOGIN refused')
  end

  describe 'the actor' do
    it 'refuses to act without one' do
      expect { described_class.new(signal: signal, actor: nil) }
        .to raise_error(described_class::InvalidAction, /operator is required/)
    end
  end

  describe '#acknowledge' do
    it 'records the operator, writes a timeline entry and an audit row' do
      expect(lifecycle.acknowledge(reason: 'Looking at it now')).to be(true)

      expect(signal.reload).to have_attributes(acknowledged_by_id: operator.id)
      expect(signal.acknowledged_at).to be_present
      expect(signal.handling_state).to eq('acknowledged')

      event = signal.events.last
      expect(event).to have_attributes(event_type: 'acknowledged', actor_id: operator.id,
                                       actor_name: 'Hisham Operator', reason: 'Looking at it now')

      audit = Custom::AuditLog.where(comment: 'operations.signal.acknowledged').last
      expect(audit.user_id).to eq(operator.id)
      expect(audit.audited_changes).to include('signal_id' => signal.id, 'source' => 'email_channel')
    end

    # An operator double-clicking must not produce two acknowledgements or two audit rows.
    it 'is idempotent' do
      lifecycle.acknowledge
      first_at = signal.reload.acknowledged_at

      expect(lifecycle.acknowledge).to be(false)
      expect(signal.reload.acknowledged_at).to eq(first_at)
      expect(signal.events.where(event_type: 'acknowledged').count).to eq(1)
      expect(Custom::AuditLog.where(comment: 'operations.signal.acknowledged').count).to eq(1)
    end

    it 'does not resolve the signal -- only an observation may' do
      lifecycle.acknowledge

      expect(signal.reload.resolved_at).to be_nil
      expect(signal).to be_open
    end
  end

  describe '#suppress' do
    it 'requires a reason' do
      expect { lifecycle.suppress(until_time: 2.hours.from_now, reason: ' ') }
        .to raise_error(described_class::InvalidAction, /reason is required/)
      expect(signal.reload.suppressed_until).to be_nil
    end

    it 'refuses a deadline in the past' do
      expect { lifecycle.suppress(until_time: 1.hour.ago, reason: 'Meta incident') }
        .to raise_error(described_class::InvalidAction, /end in the future/)
    end

    # A date-SHAPED value with an out-of-range part reaches Time.zone.parse as readily as any other string and
    # it RAISES rather than answering nil, which used to leave the controller with an unhandled ArgumentError.
    it 'refuses a date-shaped deadline that is not a real date, and writes nothing' do
      expect { lifecycle.suppress(until_time: '2026-13-45T99:99:99', reason: 'Known Meta incident') }
        .to raise_error(described_class::InvalidAction, /real date and time/)

      expect(signal.reload).to have_attributes(suppressed_until: nil, suppression_reason: nil, suppressed_by_id: nil)
      expect(signal.events).to be_empty
      expect(Custom::AuditLog.where(comment: 'operations.signal.suppressed')).to be_empty
    end

    it 'refuses an effectively permanent suppression' do
      expect { lifecycle.suppress(until_time: 90.days.from_now, reason: 'Meta incident') }
        .to raise_error(described_class::InvalidAction, /may not exceed/)
    end

    it 'suppresses with a bounded deadline and leaves the queue' do
      deadline = 6.hours.from_now

      expect(lifecycle.suppress(until_time: deadline, reason: 'Known Meta incident, tracked upstream')).to be(true)

      expect(signal.reload.suppression_reason).to eq('Known Meta incident, tracked upstream')
      expect(signal.suppressed_by_id).to eq(operator.id)
      expect(signal).to be_suppressed
      expect(signal.handling_state).to eq('suppressed')
      expect(Operations::Signal.attention_queue).not_to include(signal)
    end

    # The predicate is the clock, not a stored status, so nothing has to sweep a lapsed suppression.
    it 'returns to the queue by itself once the deadline passes' do
      lifecycle.suppress(until_time: 1.hour.from_now, reason: 'Known incident')
      expect(Operations::Signal.attention_queue).not_to include(signal)

      travel_to(2.hours.from_now) do
        expect(signal.reload).not_to be_suppressed
        expect(Operations::Signal.attention_queue).to include(signal)
      end
    end
  end

  describe '#resume' do
    it 'clears both layers so the signal returns to the queue' do
      lifecycle.acknowledge
      lifecycle.suppress(until_time: 6.hours.from_now, reason: 'Known incident')

      expect(lifecycle.resume(reason: 'Upstream says fixed')).to be(true)

      expect(signal.reload).to have_attributes(acknowledged_at: nil, acknowledged_by_id: nil,
                                               suppressed_until: nil, suppression_reason: nil,
                                               suppressed_by_id: nil)
      expect(signal.handling_state).to eq('needs_action')
      expect(Operations::Signal.attention_queue).to include(signal)
    end

    it 'is a no-op on a signal nobody has handled' do
      expect(lifecycle.resume).to be(false)
      expect(signal.events).to be_empty
    end
  end

  describe '#record_action' do
    it 'refuses an action that is not on the allow-list' do
      expect { lifecycle.record_action('rm_rf', outcome: 'ok') }
        .to raise_error(described_class::InvalidAction, /Unknown action/)
    end

    it 'records a declared action with its outcome' do
      expect(lifecycle.record_action('health_reprobe', outcome: 'recovered')).to be(true)

      expect(signal.events.last.detail).to eq('action' => 'health_reprobe', 'outcome' => 'recovered')
    end
  end

  describe 'secrets' do
    # An operator pasting a line out of a log is the realistic way a credential reaches this column, so the
    # reason is sanitized on the way in -- the same treatment Operations::SignalRecorder gives provider prose.
    it 'redacts a credential an operator pastes into a reason' do
      lifecycle.suppress(until_time: 2.hours.from_now, reason: 'imap said password=hunter2 was refused')

      expect(signal.reload.suppression_reason).to include('[redacted]')
      expect(signal.suppression_reason).not_to include('hunter2')
      expect(signal.events.last.reason).not_to include('hunter2')
    end

    it 'puts no provider detail into the audit row' do
      lifecycle.acknowledge

      audit = Custom::AuditLog.where(comment: 'operations.signal.acknowledged').last
      expect(audit.audited_changes.keys)
        .to contain_exactly('signal_id', 'source', 'signal', 'severity', 'subject_account_id', 'event')
    end

    # An operations signal is Lynomia's own record. Associating the audit row with the account would publish
    # operator activity to that account's own administrators through AuditTrail::Query.
    it 'files the audit row installation-wide, not against the customer account' do
      lifecycle.acknowledge

      audit = Custom::AuditLog.where(comment: 'operations.signal.acknowledged').last
      expect(audit.associated_id).to be_nil
      expect(Custom::AuditLog.for_account(account)).not_to include(audit)
    end
  end
end
