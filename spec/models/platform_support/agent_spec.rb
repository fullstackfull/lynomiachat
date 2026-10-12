require 'rails_helper'

RSpec.describe PlatformSupport::Agent do
  let(:super_admin) { create(:super_admin) }

  it 'has exactly two roles, with agent as the default' do
    expect(described_class.roles).to eq('agent' => 0, 'lead' => 1)
    expect(described_class.new.role).to eq('agent')
  end

  # STI constrains reads, not writes, so without this a plain tenant user id could be seeded as staff and
  # every later `find_by(user_id:)` would happily return it.
  it 'refuses a tenant user, because being a product user is not being Lynomia staff' do
    tenant = create(:user, account: create(:account), role: :administrator)
    row = described_class.new(user: tenant)

    expect(row).not_to be_valid
    expect(row.errors[:user]).to be_present
  end

  it 'accepts a super admin' do
    expect(described_class.create!(user: super_admin)).to be_persisted
  end

  it 'allows one staff row per person' do
    described_class.create!(user: super_admin)
    duplicate = described_class.new(user: super_admin)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to be_present
  end

  it 'snapshots the display name from the user and refreshes it on save' do
    agent = described_class.create!(user: super_admin)
    expect(agent.display_name).to eq(super_admin.available_name)

    super_admin.update!(display_name: 'Renamed Operator')
    agent.reload.save!

    expect(agent.reload.display_name).to eq('Renamed Operator')
  end

  it 'answers available_name with the snapshot, so the shared actor-name chain resolves a staff actor' do
    agent = described_class.create!(user: super_admin)
    expect(agent.available_name).to eq(agent.display_name)
  end

  describe 'deactivation' do
    it 'is how an operator leaves the desk: the row survives and the active scope drops it' do
      agent = described_class.create!(user: super_admin)
      agent.update!(active: false)

      expect(described_class.active).not_to include(agent)
      expect(agent.reload).to be_persisted
    end
  end

  describe 'what happens to their work' do
    let(:account) { create(:account) }
    let(:agent) { described_class.create!(user: super_admin) }
    let(:ticket) do
      PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                      reporter_name: 'Reporter', subject: 'Something', assignee: agent)
    end

    it 'returns their assigned tickets to the unassigned queue when the row goes' do
      ticket
      agent.destroy!

      expect(ticket.reload.assignee_id).to be_nil
    end

    it 'refuses to delete a row that has written internal notes, so authorship cannot be erased' do
      PlatformSupport::InternalNote.create!(ticket: ticket, agent: agent, body: 'Escalated to engineering')

      expect(agent.destroy).to be(false)
      expect(agent.errors[:base].join).to match(/internal notes/i)
      expect(agent.reload).to be_persisted
    end
  end
end
