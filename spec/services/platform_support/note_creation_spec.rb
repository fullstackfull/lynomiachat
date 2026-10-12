require 'rails_helper'

RSpec.describe PlatformSupport::NoteCreation do
  let(:account) { create(:account) }
  let(:reporter) { create(:user, account: account, role: :administrator) }
  let(:agent) { PlatformSupport::Agent.create!(user: create(:super_admin)) }
  let(:ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter: reporter, reporter_name: reporter.available_name,
                                    subject: 'Template stuck')
  end
  let(:audits) { Custom::AuditLog.where(auditable_type: 'PlatformSupport::Ticket') }

  let(:note) do
    described_class.new(ticket: ticket, agent: agent, body: 'Meta ticket 4471, chasing their TAM').perform
  end

  it 'writes the note under the agent\'s snapshot name' do
    expect(note).to have_attributes(agent_id: agent.id, author_name: agent.display_name,
                                    body: 'Meta ticket 4471, chasing their TAM')
  end

  it 'puts nothing in the public thread' do
    note
    expect(ticket.reload.messages).to be_empty
  end

  it 'records internal_note_added, which the customer cannot see, so the note\'s existence is hidden too' do
    note

    expect(ticket.reload.events.pluck(:event_type)).to eq(['internal_note_added'])
    expect(ticket.events.customer_visible).to be_empty
  end

  it 'audits the note with the agent\'s own user and keeps the body out of the row' do
    ticket
    agent

    expect { note }.to change(audits, :count).by(1)

    audit = audits.last
    expect(audit).to have_attributes(user_id: agent.user_id, comment: 'platform_support.internal_note_added',
                                     associated_type: nil, associated_id: nil)
    expect(audit.audited_changes).to include('note_id' => note.id, 'agent_id' => agent.id)
    expect(audit.audited_changes.to_s).not_to include('Meta ticket 4471')
  end

  it 'puts no body in the event metadata either' do
    expect(note).to be_present
    expect(ticket.reload.events.first.metadata).to eq('note_id' => note.id)
  end

  it 'moves last_activity_at, so a noted ticket rises in the staff queue' do
    ticket.update!(last_activity_at: 3.days.ago)
    note

    expect(ticket.reload.last_activity_at).to be_within(5.seconds).of(Time.current)
  end

  it 'rolls everything back when the note is unusable' do
    ticket

    expect { described_class.new(ticket: ticket, agent: agent, body: '').perform }
      .to raise_error(ActiveRecord::RecordInvalid)

    expect(ticket.reload.events).to be_empty
    expect(audits.count).to eq(0)
  end
end
