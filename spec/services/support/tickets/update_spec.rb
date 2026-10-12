require 'rails_helper'

RSpec.describe Support::Tickets::Update do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:policy) do
    create(:support_sla_policy, account: account, first_response_time_threshold: 1.hour.to_i,
                                resolution_time_threshold: 4.hours.to_i)
  end
  let(:ticket) { create(:support_ticket, account: account) }

  def update(attributes, on: ticket, by: agent)
    described_class.new(ticket: on, user: by, attributes: attributes).perform
  end

  describe 'status transitions' do
    it 'refuses an edge the table does not allow, and leaves the case untouched' do
      update({ status: 'closed' })

      expect { update({ status: 'resolved' }) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Tickets::InvalidStatusTransition') })
      expect(ticket.reload).to be_closed
    end

    it 'stamps resolved_at and keeps it when the case is then closed' do
      update({ status: 'resolved' })
      resolved_at = ticket.reload.resolved_at
      expect(resolved_at).to be_present

      update({ status: 'closed' })
      ticket.reload

      expect(ticket.resolved_at).to eq(resolved_at)
      expect(ticket.closed_at).to be_present
    end

    it 'clears both timestamps on reopen' do
      update({ status: 'resolved' })
      update({ status: 'open' })
      ticket.reload

      expect(ticket.resolved_at).to be_nil
      expect(ticket.closed_at).to be_nil
    end
  end

  describe 'the SLA clock' do
    it 'starts when a policy is attached for the first time' do
      update({ sla_policy_id: policy.id })
      ticket.reload

      expect(ticket.first_response_due_at).to be_present
      expect(ticket.resolution_due_at).to be_present
      expect(ticket.events.pluck(:event_type)).to include('sla_applied')
    end

    it 'pauses only on waiting_on_customer' do
      update({ sla_policy_id: policy.id })

      update({ status: 'waiting_on_internal' })
      expect(ticket.reload.sla_paused_at).to be_nil

      update({ status: 'waiting_on_customer' })
      expect(ticket.reload.sla_paused_at).to be_present
    end

    it 'resumes and credits the pause when the case moves on' do
      update({ sla_policy_id: policy.id })
      due_before = ticket.reload.resolution_due_at
      update({ status: 'waiting_on_customer' })
      ticket.update!(sla_paused_at: 30.minutes.ago)

      update({ status: 'in_progress' }, on: ticket.reload)
      ticket.reload

      expect(ticket.sla_paused_at).to be_nil
      expect(ticket.sla_paused_seconds).to be_within(60).of(30.minutes.to_i)
      expect(ticket.resolution_due_at).to be > due_before
    end

    it 'gives a reopened case a fresh resolution target and clears the breach' do
      update({ sla_policy_id: policy.id })
      update({ status: 'resolved' })
      ticket.update!(resolution_breached_at: 1.hour.ago, resolution_due_at: 2.hours.ago)

      update({ status: 'open' }, on: ticket.reload)
      ticket.reload

      expect(ticket.resolution_breached_at).to be_nil
      expect(ticket.resolution_due_at).to be > Time.current
    end

    # A due time is a commitment made when the policy was attached. Re-dating it on an edit would make the SLA
    # unfalsifiable.
    it 'does not move the due times when the priority changes' do
      update({ sla_policy_id: policy.id })
      before = ticket.reload.resolution_due_at

      update({ priority: 'urgent' })

      expect(ticket.reload.resolution_due_at).to eq(before)
    end
  end

  describe 'the event trail' do
    it 'writes one row per change, named for the outcome an operator looks for' do
      update({ status: 'in_progress' })
      update({ assignee_id: other_agent.id })
      update({ team_id: team.id })
      update({ priority: 'high' })
      update({ category: 'billing' })
      update({ status: 'resolved' })
      update({ status: 'open' })

      expect(ticket.events.pluck(:event_type)).to eq(
        %w[status_changed assigned team_changed priority_changed category_changed resolved reopened]
      )
    end

    it 'records what changed, with values and not prose' do
      update({ priority: 'urgent' })
      event = ticket.events.find_by(event_type: 'priority_changed')

      expect(event.data).to eq('from' => 'medium', 'to' => 'urgent')
      expect(event.user_id).to eq(agent.id)
    end

    it 'distinguishes linking a conversation from unlinking one' do
      conversation = create(:conversation, account: account)
      update({ conversation_id: conversation.id })
      update({ conversation_id: nil })

      expect(ticket.events.pluck(:event_type)).to eq(%w[conversation_linked conversation_unlinked])
    end

    it 'writes nothing for an unchanged attribute' do
      update({ priority: 'medium' })

      expect(ticket.events).to be_empty
    end
  end

  it 'bumps last_activity_at so the list sorts by real activity' do
    ticket.update!(last_activity_at: 3.days.ago)

    update({ priority: 'high' })

    expect(ticket.reload.last_activity_at).to be_within(5.seconds).of(Time.current)
  end
end
