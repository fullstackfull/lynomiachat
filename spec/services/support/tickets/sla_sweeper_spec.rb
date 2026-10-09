require 'rails_helper'

RSpec.describe Support::Tickets::SlaSweeper do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:policy) do
    create(:support_sla_policy, account: account, first_response_time_threshold: 1.hour.to_i,
                                resolution_time_threshold: 4.hours.to_i)
  end

  describe 'first response' do
    it 'records a reply that arrived inside the target as met' do
      ticket = create(:support_ticket, account: account, conversation: conversation, sla_policy: policy,
                                       created_at: 3.hours.ago, first_response_due_at: 2.hours.ago)
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, created_at: 2.5.hours.ago)

      counts = described_class.new.perform
      ticket.reload

      expect(counts[:first_response_met]).to eq(1)
      expect(ticket.first_responded_at).to be_present
      expect(ticket.first_response_breached_at).to be_nil
      expect(ticket.events.pluck(:event_type)).to include('sla_first_response_met')
    end

    # The comparison is message time against due time, never sweep time, so a sweep that runs late cannot turn a
    # met target into a breach -- and a reply that really was late is still recorded as late.
    it 'records a reply that arrived after the target as breached, at the reply time' do
      ticket = create(:support_ticket, account: account, conversation: conversation, sla_policy: policy,
                                       created_at: 5.hours.ago, first_response_due_at: 4.hours.ago)
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, created_at: 2.hours.ago)

      counts = described_class.new.perform
      ticket.reload

      expect(counts[:first_response_breached]).to eq(1)
      expect(ticket.first_response_breached_at).to be_within(1.minute).of(2.hours.ago)
    end

    it 'breaches a case past its target with no reply at all' do
      ticket = create(:support_ticket, account: account, conversation: conversation, sla_policy: policy,
                                       created_at: 3.hours.ago, first_response_due_at: 2.hours.ago)

      described_class.new.perform

      expect(ticket.reload.first_response_breached_at).to be_present
    end

    it 'ignores an inbound message and a private note' do
      ticket = create(:support_ticket, account: account, conversation: conversation, sla_policy: policy,
                                       created_at: 3.hours.ago, first_response_due_at: 2.hours.ago)
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :incoming, created_at: 2.5.hours.ago)
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, private: true, created_at: 2.5.hours.ago)

      described_class.new.perform
      ticket.reload

      expect(ticket.first_responded_at).to be_nil
      expect(ticket.first_response_breached_at).to be_present
    end

    # A reply that predates the case is a reply to something else.
    it 'ignores a reply sent before the case was opened' do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :outgoing, created_at: 6.hours.ago)
      ticket = create(:support_ticket, account: account, conversation: conversation, sla_policy: policy,
                                       created_at: 3.hours.ago, first_response_due_at: 2.hours.ago)

      described_class.new.perform

      expect(ticket.reload.first_responded_at).to be_nil
    end

    it 'leaves a paused case alone' do
      ticket = create(:support_ticket, account: account, conversation: conversation, sla_policy: policy,
                                       status: :waiting_on_customer, created_at: 3.hours.ago,
                                       first_response_due_at: 2.hours.ago, sla_paused_at: 2.5.hours.ago)

      described_class.new.perform

      expect(ticket.reload.first_response_breached_at).to be_nil
    end

    it 'has nothing to detect for a case with no conversation, and does not pretend otherwise' do
      ticket = create(:support_ticket, account: account, sla_policy: policy, created_at: 3.hours.ago,
                                       first_response_due_at: 2.hours.ago)

      described_class.new.perform
      ticket.reload

      expect(ticket.first_responded_at).to be_nil
      expect(ticket.first_response_breached_at).to be_present
    end
  end

  describe 'resolution' do
    it 'breaches an active case past its resolution target' do
      ticket = create(:support_ticket, account: account, sla_policy: policy, resolution_due_at: 1.hour.ago)

      counts = described_class.new.perform
      ticket.reload

      expect(counts[:resolution_breached]).to eq(1)
      expect(ticket.resolution_breached_at).to be_present
      expect(ticket.events.pluck(:event_type)).to include('sla_resolution_breached')
    end

    it 'leaves a resolved case alone, however late it was' do
      ticket = create(:support_ticket, account: account, sla_policy: policy, status: :resolved,
                                       resolution_due_at: 3.days.ago)

      described_class.new.perform

      expect(ticket.reload.resolution_breached_at).to be_nil
    end

    it 'leaves a case with no policy alone' do
      ticket = create(:support_ticket, account: account, resolution_due_at: 1.hour.ago)

      described_class.new.perform

      expect(ticket.reload.resolution_breached_at).to be_nil
    end

    it 'never writes a breach twice' do
      ticket = create(:support_ticket, account: account, sla_policy: policy, resolution_due_at: 1.hour.ago)

      described_class.new.perform
      first = ticket.reload.resolution_breached_at
      second_run = described_class.new.perform

      expect(second_run[:resolution_breached]).to eq(0)
      expect(ticket.reload.resolution_breached_at).to eq(first)
      expect(ticket.events.where(event_type: 'sla_resolution_breached').count).to eq(1)
    end
  end

  it 'reports nothing when there is nothing to decide' do
    create(:support_ticket, account: account)

    expect(described_class.new.perform.values.sum).to eq(0)
  end
end
