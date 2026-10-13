require 'rails_helper'

RSpec.describe PlatformSupport::TicketTransition do
  let(:account) { create(:account) }
  let(:reporter) { create(:user, account: account, role: :administrator) }
  let(:agent) { PlatformSupport::Agent.create!(user: create(:super_admin)) }
  let(:ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter: reporter, reporter_name: reporter.available_name,
                                    subject: 'Template stuck', priority: :medium, category: 'whatsapp')
  end
  let(:audits) { Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket') }

  describe 'the status event names' do
    it 'calls an ordinary move status_changed' do
      described_class.new(ticket: ticket, actor: agent, attributes: { status: 'in_progress' }).perform

      expect(ticket.reload.events.pluck(:event_type)).to eq(['status_changed'])
    end

    it 'calls resolving it resolved, and stamps resolved_at' do
      described_class.new(ticket: ticket, actor: agent, attributes: { status: 'resolved' }).perform

      expect(ticket.reload.events.pluck(:event_type)).to eq(['resolved'])
      expect(ticket.resolved_at).to be_present
    end

    it 'calls closing it closed, and keeps resolved_at so "resolved Monday, closed Friday" stays readable' do
      ticket.update!(status: :resolved, resolved_at: 3.days.ago)
      described_class.new(ticket: ticket, actor: agent, attributes: { status: 'closed' }).perform

      expect(ticket.reload.events.pluck(:event_type)).to eq(['closed'])
      expect(ticket.resolved_at).to be_present
      expect(ticket.closed_at).to be_present
    end

    it 'calls coming back from a terminal state reopened, and clears both stamps' do
      ticket.update!(status: :closed, resolved_at: 3.days.ago, closed_at: 1.day.ago)
      described_class.new(ticket: ticket, actor: agent, attributes: { status: 'open' }).perform

      expect(ticket.reload.events.pluck(:event_type)).to eq(['reopened'])
      expect(ticket).to have_attributes(resolved_at: nil, closed_at: nil)
    end

    it 'records nothing for a no-op, so an idempotent retry does not litter the history' do
      described_class.new(ticket: ticket, actor: agent, attributes: { status: 'open' }).perform

      expect(ticket.reload.events).to be_empty
    end
  end

  describe 'triage' do
    it 'records a priority change, which the customer is deliberately not shown' do
      described_class.new(ticket: ticket, actor: agent, attributes: { priority: 'urgent' }).perform

      expect(ticket.reload.priority).to eq('urgent')
      expect(ticket.events.pluck(:event_type)).to eq(['priority_changed'])
      expect(PlatformSupport::Event::CUSTOMER_VISIBLE_EVENT_TYPES).not_to include('priority_changed')
    end

    it 'records a category change and a subject change separately' do
      described_class.new(ticket: ticket, actor: agent,
                          attributes: { category: 'performance', subject: 'Dashboard slow' }).perform

      expect(ticket.reload.events.pluck(:event_type)).to contain_exactly('category_changed', 'subject_changed')
    end

    it 'records one event per field that actually changed and none for the rest' do
      described_class.new(ticket: ticket, actor: agent,
                          attributes: { priority: 'urgent', category: 'whatsapp', status: 'in_progress' }).perform

      expect(ticket.reload.events.pluck(:event_type)).to contain_exactly('status_changed', 'priority_changed')
    end

    it 'ignores anything outside the four tracked fields' do
      described_class.new(ticket: ticket, actor: agent,
                          attributes: { assignee_id: 99, reference_number: 7 }).perform

      expect(ticket.reload).to have_attributes(assignee_id: nil)
      expect(ticket.reference_number).not_to eq(7)
    end
  end

  # THE PAUSE RULE, applied on every status change by the one writer rather than by each caller. Thresholds
  # are the factory's synthetic seconds; no production target lives in this repository (D-7).
  describe 'the SLA clock' do
    let(:policy) { create(:platform_support_sla_policy) }

    before do
      ticket.sla_policy = policy
      PlatformSupport::Sla::Clock.new(ticket).apply(from: Time.current)
      ticket.save!
    end

    it 'stops the clock when the ticket starts waiting on the customer' do
      described_class.new(ticket: ticket, actor: agent, attributes: { status: 'waiting_on_customer' }).perform

      expect(ticket.reload.sla_paused_at).to be_present
    end

    # The non-obvious half, and it is deliberate: waiting on ourselves is our own delay.
    it 'does not stop it when the ticket is waiting on Lynomia' do
      described_class.new(ticket: ticket, actor: agent, attributes: { status: 'waiting_on_lynomia' }).perform

      expect(ticket.reload.sla_paused_at).to be_nil
    end

    it 'restarts it on the way out, having moved the outstanding targets on by the time it stood still' do
      described_class.new(ticket: ticket, actor: agent, attributes: { status: 'waiting_on_customer' }).perform
      paused_due = ticket.reload.resolution_due_at

      described_class.new(ticket: ticket, actor: agent, attributes: { status: 'in_progress' }).perform

      expect(ticket.reload.sla_paused_at).to be_nil
      expect(ticket.sla_paused_seconds).to be >= 0
      expect(ticket.resolution_due_at).to be >= paused_due
    end

    it 'writes no history row of its own: a pause is not something the customer was told' do
      described_class.new(ticket: ticket, actor: agent, attributes: { status: 'waiting_on_customer' }).perform

      expect(ticket.reload.events.pluck(:event_type)).to eq(['status_changed'])
    end
  end

  # Two statuses ASK the customer something; every other transition is Lynomia's own bookkeeping, and a mail
  # per status change would train the customer to ignore the two that matter.
  describe 'the customer email' do
    it 'mails on resolved' do
      expect { described_class.new(ticket: ticket, actor: agent, attributes: { status: 'resolved' }).perform }
        .to have_enqueued_mail(PlatformSupport::TicketMailer, :ticket_resolved)
    end

    it 'mails on waiting_on_customer' do
      expect do
        described_class.new(ticket: ticket, actor: agent, attributes: { status: 'waiting_on_customer' }).perform
      end.to have_enqueued_mail(PlatformSupport::TicketMailer, :waiting_on_customer)
    end

    it 'says nothing on an ordinary move, or on a change that is not a status change at all' do
      expect do
        described_class.new(ticket: ticket, actor: agent, attributes: { status: 'in_progress' }).perform
        described_class.new(ticket: ticket, actor: agent, attributes: { priority: 'urgent' }).perform
      end.not_to have_enqueued_mail(PlatformSupport::TicketMailer)
    end
  end

  describe 'the audit trail' do
    it 'files one installation-wide row per staff change, with the agent\'s own user as the actor' do
      ticket
      agent

      expect do
        described_class.new(ticket: ticket, actor: agent, attributes: { status: 'resolved' }).perform
      end.to change(audits, :count).by(1)

      expect(audits.last).to have_attributes(user_id: agent.user_id, comment: 'platform_support.resolved',
                                             associated_type: nil, associated_id: nil)
    end

    it 'carries ids, enums and the reference only' do
      described_class.new(ticket: ticket, actor: agent, attributes: { priority: 'urgent' }).perform

      expect(audits.last.audited_changes).to include(
        'ticket_id' => ticket.id, 'reference' => ticket.reference, 'subject_account_id' => account.id,
        'event' => 'priority_changed', 'from' => 'medium', 'to' => 'urgent', 'agent_id' => agent.id
      )
    end

    it 'files nothing for a customer\'s own change, which is in their ticket\'s history instead' do
      ticket

      expect do
        described_class.new(ticket: ticket, actor: reporter, attributes: { priority: 'urgent' }).perform
      end.not_to change(audits, :count)

      expect(ticket.reload.events.first).to have_attributes(event_type: 'priority_changed', actor_type: 'User')
    end
  end

  it 'moves last_activity_at, which is what the list orders by' do
    ticket.update!(last_activity_at: 3.days.ago)
    described_class.new(ticket: ticket, actor: agent, attributes: { status: 'in_progress' }).perform

    expect(ticket.reload.last_activity_at).to be_within(5.seconds).of(Time.current)
  end
end
