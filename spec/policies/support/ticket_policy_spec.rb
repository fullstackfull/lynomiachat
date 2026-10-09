require 'rails_helper'

RSpec.describe Support::TicketPolicy do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }
  let(:lead_role) { create(:custom_role, account: account, permissions: ['support_ticket_manage']) }

  let(:mine) { create(:support_ticket, account: account, assignee: agent) }
  let(:my_teams) { create(:support_ticket, account: account, team: team) }
  let(:i_opened) { create(:support_ticket, account: account, created_by: agent) }
  let(:someone_elses) { create(:support_ticket, account: account, assignee: administrator) }

  def context_for(user)
    { user: user, account: account, account_user: AccountUser.find_by(account: account, user: user) }
  end

  def visible_to(user)
    described_class::Scope.new(context_for(user), Support::Ticket.where(account_id: account.id)).resolve
  end

  before do
    AccountUser.find_by(account: account, user: lead).update!(custom_role: lead_role)
    create(:team_member, team: team, user: agent)
  end

  describe 'an administrator' do
    it 'sees every case in the account' do
      expect(visible_to(administrator)).to contain_exactly(mine, my_teams, i_opened, someone_elses)
    end
  end

  describe 'an agent whose custom role grants support_ticket_manage' do
    it 'sees every case in the account' do
      expect(visible_to(lead)).to contain_exactly(mine, my_teams, i_opened, someone_elses)
    end
  end

  describe 'an ordinary agent' do
    it 'sees the cases assigned to them, to their team, or that they opened' do
      expect(visible_to(agent)).to contain_exactly(mine, my_teams, i_opened)
    end

    it "does not see somebody else's case" do
      expect(visible_to(agent)).not_to include(someone_elses)
    end

    # Visibility is ownership, not channel: a case can have no inbox at all, and its title may describe a
    # customer the reader has no business seeing.
    it 'does not gain visibility from inbox membership alone' do
      inbox = create(:inbox, account: account)
      create(:inbox_member, user: agent, inbox: inbox)
      in_my_inbox = create(:support_ticket, account: account, inbox: inbox, assignee: administrator)

      expect(visible_to(agent)).not_to include(in_my_inbox)
    end
  end

  describe 'record level' do
    it 'asks the same scope, so show? and update? cannot disagree with the list' do
      policy = described_class.new(context_for(agent), someone_elses)
      expect(policy.show?).to be(false)
      expect(policy.update?).to be(false)

      own = described_class.new(context_for(agent), mine)
      expect(own.show?).to be(true)
      expect(own.update?).to be(true)
    end

    it 'never allows a delete' do
      expect(described_class.new(context_for(administrator), mine).destroy?).to be(false)
    end
  end

  it 'never leaks across accounts, whatever the role' do
    theirs = create(:support_ticket, account: other_account)

    expect(visible_to(administrator)).not_to include(theirs)
    expect(visible_to(lead)).not_to include(theirs)
  end
end
