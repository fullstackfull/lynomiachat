require 'rails_helper'

RSpec.describe PlatformSupport::MessageCreation do
  let(:account) { create(:account) }
  let(:reporter) { create(:user, account: account, role: :administrator) }
  let(:agent) { PlatformSupport::Agent.create!(user: create(:super_admin)) }
  let(:ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter: reporter, reporter_name: reporter.available_name,
                                    subject: 'Template stuck')
  end

  describe 'a customer reply' do
    let(:message) do
      described_class.new(ticket: ticket, author: reporter, body: 'Still not working').perform
    end

    it 'lands as a customer message and stamps the customer clock' do
      expect(message).to have_attributes(author_type: 'User', author_id: reporter.id, body: 'Still not working')
      expect(ticket.reload.last_customer_message_at).to be_present
      expect(ticket.last_operator_message_at).to be_nil
    end

    it 'records customer_replied, which the customer is allowed to see' do
      expect(message).to be_present
      expect(ticket.reload.events.pluck(:event_type)).to eq(['customer_replied'])
      expect(PlatformSupport::Event::CUSTOMER_VISIBLE_EVENT_TYPES).to include('customer_replied')
    end

    it 'writes no audit row: the customer can already read their own reply' do
      ticket
      expect { message }.not_to change(Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket'), :count)
    end

    it 'does not stamp first_responded_at, because the customer is not the response' do
      expect(message).to be_present
      expect(ticket.reload.first_responded_at).to be_nil
    end
  end

  describe 'an operator reply' do
    let(:message) do
      described_class.new(ticket: ticket, author: agent, body: 'We have escalated this to Meta').perform
    end

    it 'lands as an operator message and stamps the operator clock' do
      expect(message).to have_attributes(author_type: 'PlatformSupport::Agent', author_id: agent.id)
      expect(ticket.reload.last_operator_message_at).to be_present
    end

    it 'stamps first_responded_at the first time only' do
      first = message
      ticket.reload
      stamped = ticket.first_responded_at
      expect(stamped).to eq(first.created_at)

      described_class.new(ticket: ticket, author: agent, body: 'Still chasing').perform

      expect(ticket.reload.first_responded_at).to eq(stamped)
    end

    it 'makes the ticket unread for the customer' do
      expect(message).to be_present
      expect(ticket.reload).to be_unread
    end

    it 'records operator_replied and audits it with the agent\'s own user as the actor' do
      ticket
      agent
      expect { message }.to change(Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket'), :count).by(1)

      audit = Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket').last
      expect(audit).to have_attributes(user_id: agent.user_id, comment: 'platform_support.operator_replied',
                                       associated_type: nil, associated_id: nil)
      expect(ticket.reload.events.pluck(:event_type)).to eq(['operator_replied'])
    end

    it 'keeps the reply body out of the audit row' do
      message
      audit = Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket').last
      expect(audit.audited_changes.to_s).not_to include('escalated this to Meta')
    end
  end

  describe 'a resolved ticket' do
    before { ticket.update!(status: :resolved, resolved_at: Time.current) }

    it 'reopens on a customer reply, because resolved is Lynomia\'s claim and not the customer\'s' do
      described_class.new(ticket: ticket, author: reporter, body: 'It is not fixed').perform

      expect(ticket.reload).to have_attributes(status: 'open', resolved_at: nil, closed_at: nil)
      expect(ticket.events.pluck(:event_type)).to contain_exactly('reopened', 'customer_replied')
    end

    it 'clears a recorded resolution breach on reopen, leaving the fresh due time to the SLA engine' do
      ticket.update!(resolution_breached_at: 1.hour.ago, resolution_due_at: 2.hours.ago)
      described_class.new(ticket: ticket, author: reporter, body: 'Still broken').perform

      expect(ticket.reload.resolution_breached_at).to be_nil
    end

    it 'does not reopen on an operator reply: finishing a thought is not reopening the work' do
      described_class.new(ticket: ticket, author: agent, body: 'For the record, the fix shipped').perform

      expect(ticket.reload.status).to eq('resolved')
      expect(ticket.events.pluck(:event_type)).to eq(['operator_replied'])
    end
  end

  describe 'a closed ticket' do
    before { ticket.update!(status: :closed, closed_at: Time.current) }

    it 'refuses the reply with the 422 that tells the customer what to do instead' do
      expect { described_class.new(ticket: ticket, author: reporter, body: 'Hello again').perform }
        .to raise_error(CustomExceptions::PlatformTickets::TicketClosed) { |error|
          expect(error.http_status).to eq(422)
          expect(error.message).to eq('This ticket is closed. Open a new one.')
        }
    end

    it 'writes nothing at all when it refuses' do
      expect do
        described_class.new(ticket: ticket, author: reporter, body: 'Hello again').perform
      rescue CustomExceptions::PlatformTickets::TicketClosed
        nil
      end.not_to change(PlatformSupport::Message, :count)
    end

    it 'refuses an operator reply too, so the rule is not one side\'s only' do
      expect { described_class.new(ticket: ticket, author: agent, body: 'One more thing').perform }
        .to raise_error(CustomExceptions::PlatformTickets::TicketClosed)
    end
  end

  it 'moves last_activity_at on every reply, which is what the list orders by' do
    ticket.update!(last_activity_at: 3.days.ago)
    described_class.new(ticket: ticket, author: reporter, body: 'Any news?').perform

    expect(ticket.reload.last_activity_at).to be_within(5.seconds).of(Time.current)
  end
end
