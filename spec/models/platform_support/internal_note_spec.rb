require 'rails_helper'

RSpec.describe PlatformSupport::InternalNote do
  let(:account) { create(:account) }
  let(:agent) { PlatformSupport::Agent.create!(user: create(:super_admin)) }
  let(:ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter_name: 'Reporter', subject: 'Template stuck')
  end

  it 'is a table of its own, with no visibility column anybody could forget' do
    expect(described_class.column_names).not_to include('visibility', 'private', 'public')
    expect(described_class.table_name).to eq('platform_support_internal_notes')
  end

  it 'has no author type, because a note is always written by an agent' do
    expect(described_class.column_names).not_to include('author_type')
  end

  it 'requires the agent who wrote it' do
    note = described_class.new(ticket: ticket, body: 'Escalated')
    expect(note).not_to be_valid
    expect(note.errors[:agent]).to be_present
  end

  it 'snapshots the author name from the agent rather than accepting one' do
    note = described_class.create!(ticket: ticket, agent: agent, body: 'Escalated to engineering',
                                   author_name: 'Somebody Else')

    expect(note.author_name).to eq(agent.display_name)
  end

  it 'requires a body and caps it at 10 000 characters' do
    note = described_class.new(ticket: ticket, agent: agent, body: 'a' * 10_001)
    expect(note).not_to be_valid
    expect(note.errors[:body]).to be_present
  end

  # The one association a tenant-visible object must never offer a path to.
  it 'is reachable from the ticket and from nothing a tenant serializer reads' do
    described_class.create!(ticket: ticket, agent: agent, body: 'Internal')

    expect(ticket.reload.internal_notes.count).to eq(1)
    expect(ticket.messages).to be_empty
  end

  it 'dies with its ticket, so account teardown leaves no orphan' do
    described_class.create!(ticket: ticket, agent: agent, body: 'Internal')
    PlatformSupport::Ticket.where(id: ticket.id).delete_all

    expect(described_class.where(platform_support_ticket_id: ticket.id)).to be_empty
  end
end
