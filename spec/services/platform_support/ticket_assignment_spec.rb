require 'rails_helper'

RSpec.describe PlatformSupport::TicketAssignment do
  let(:account) { create(:account) }
  let(:agent) { PlatformSupport::Agent.create!(user: create(:super_admin)) }
  let(:other_agent) { PlatformSupport::Agent.create!(user: create(:super_admin)) }
  let(:lead) { PlatformSupport::Agent.create!(user: create(:super_admin), role: :lead) }
  let(:ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter_name: 'Reporter', subject: 'Template stuck')
  end
  let(:audits) { Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket') }

  it 'assigns, records the event and audits it' do
    ticket
    agent

    expect do
      described_class.new(ticket: ticket, actor: agent, assignee: agent).perform
    end.to change(audits, :count).by(1)

    expect(ticket.reload.assignee_id).to eq(agent.id)
    expect(ticket.events.pluck(:event_type)).to eq(['assigned'])
    expect(audits.last).to have_attributes(comment: 'platform_support.assigned', user_id: agent.user_id,
                                           associated_type: nil)
  end

  it 'unassigns, with its own event name' do
    described_class.new(ticket: ticket, actor: agent, assignee: agent).perform
    described_class.new(ticket: ticket, actor: lead, assignee: nil).perform

    expect(ticket.reload.assignee_id).to be_nil
    expect(ticket.events.pluck(:event_type)).to eq(%w[assigned unassigned])
  end

  it 'records the handover from one agent to another in the metadata' do
    described_class.new(ticket: ticket, actor: agent, assignee: agent).perform
    described_class.new(ticket: ticket, actor: lead, assignee: other_agent).perform

    expect(ticket.reload.events.last.metadata).to eq('from' => agent.id, 'to' => other_agent.id)
  end

  it 'does nothing at all when the assignment is unchanged' do
    described_class.new(ticket: ticket, actor: agent, assignee: agent).perform

    expect do
      described_class.new(ticket: ticket, actor: agent, assignee: agent).perform
    end.not_to change(ticket.reload.events, :count)
  end

  it 'keeps assignment out of what the customer is shown' do
    described_class.new(ticket: ticket, actor: agent, assignee: agent).perform

    expect(ticket.reload.events.customer_visible).to be_empty
  end

  # The one structural guarantee: the column's foreign key points at platform_support_agents, so no tenant
  # user id can be written to it and no AccountUser is ever needed for staff.
  it 'cannot hold a tenant user id' do
    tenant = create(:user, account: account, role: :administrator)

    # Asserted against the database rather than the model, because the guarantee IS the foreign key: even a
    # caller that bypasses every validation cannot write a tenant user id here.
    expect do
      ActiveRecord::Base.connection.execute(
        "UPDATE platform_support_tickets SET assignee_id = #{tenant.id} WHERE id = #{ticket.id}"
      )
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'returns an assigned ticket to the unassigned queue when the agent row goes' do
    described_class.new(ticket: ticket, actor: agent, assignee: agent).perform
    agent.destroy!

    expect(ticket.reload.assignee_id).to be_nil
  end
end
