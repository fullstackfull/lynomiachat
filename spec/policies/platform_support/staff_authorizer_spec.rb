require 'rails_helper'

RSpec.describe PlatformSupport::StaffAuthorizer do
  let(:account) { create(:account) }
  let(:super_admin) { create(:super_admin) }
  let(:agent) { PlatformSupport::Agent.create!(user: super_admin) }
  let(:other_agent) { PlatformSupport::Agent.create!(user: create(:super_admin)) }
  let(:lead) { PlatformSupport::Agent.create!(user: create(:super_admin), role: :lead) }
  let(:ticket) do
    PlatformSupport::Ticket.create!(account: account, account_name_at_creation: account.name,
                                    reporter_name: 'Reporter', subject: 'Template stuck')
  end

  describe '.agent_for' do
    it 'finds the staff row for an authenticated super admin' do
      agent
      expect(described_class.agent_for(super_admin)).to eq(agent)
    end

    # Being a Super Admin is not being support staff.
    it 'answers nil for a super admin who has no staff row' do
      expect(described_class.agent_for(create(:super_admin))).to be_nil
    end

    it 'answers nil for a deactivated row, so leaving the desk takes effect without deleting the notes' do
      agent.update!(active: false)

      expect(described_class.agent_for(super_admin)).to be_nil
    end

    it 'answers nil for no authenticated super admin at all' do
      expect(described_class.agent_for(nil)).to be_nil
    end

    # The desk's correct starting state: no rows are seeded anywhere, so every staff action is refused until
    # an operator deliberately creates one.
    it 'answers nil for everybody while no agent rows exist' do
      expect(PlatformSupport::Agent.count).to eq(0)
      expect(described_class.agent_for(create(:super_admin))).to be_nil
    end
  end

  describe '#staff?' do
    it 'is false without a row and true with one' do
      expect(described_class.new(nil)).not_to be_staff
      expect(described_class.new(agent)).to be_staff
    end
  end

  describe '#may_assign?' do
    it 'lets an agent pick up unassigned work' do
      expect(described_class.new(agent).may_assign?(ticket)).to be(true)
    end

    it 'lets an agent hand back their own ticket' do
      ticket.update!(assignee: agent)

      expect(described_class.new(agent).may_assign?(ticket)).to be(true)
    end

    it 'refuses an agent taking a ticket off another agent' do
      ticket.update!(assignee: other_agent)

      expect(described_class.new(agent).may_assign?(ticket)).to be(false)
    end

    it 'lets a lead reassign anybody\'s ticket' do
      ticket.update!(assignee: other_agent)

      expect(described_class.new(lead).may_assign?(ticket)).to be(true)
    end

    it 'refuses somebody with no staff row outright' do
      expect(described_class.new(nil).may_assign?(ticket)).to be(false)
    end
  end

  describe '#may_edit_sla_policies?' do
    it 'is a lead decision, because a threshold is Lynomia\'s commercial commitment' do
      expect(described_class.new(lead).may_edit_sla_policies?).to be(true)
      expect(described_class.new(agent).may_edit_sla_policies?).to be(false)
      expect(described_class.new(nil).may_edit_sla_policies?).to be(false)
    end
  end

  # Session isolation, made structural: Warden keys both Devise scopes into one cookie, so one browser can hold
  # a tenant session and a Super Admin session at once.
  it 'shares no method name with the tenant policy, so neither surface can authorize through the other' do
    staff_methods = described_class.instance_methods(false) + described_class.methods(false)
    tenant_methods = PlatformSupport::TicketPolicy.instance_methods(false) +
                     PlatformSupport::TicketPolicy::Scope.instance_methods(false)

    expect(staff_methods & tenant_methods).to be_empty
    expect(described_class.ancestors).not_to include(ApplicationPolicy)
    # It takes the acting super admin as an argument; there is no path by which an ambient tenant session
    # could become staff authority.
    expect(described_class.method(:agent_for).arity).to eq(1)
  end
end
