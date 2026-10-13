require 'rails_helper'

RSpec.describe PlatformSupport::TicketPolicy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:second_agent) { create(:user, account: account, role: :agent) }
  let(:custom_role) { create(:custom_role, account: account, permissions: %w[conversation_manage contact_manage]) }
  let(:custom_role_holder) do
    user = create(:user, account: account, role: :agent)
    AccountUser.find_by(account_id: account.id, user_id: user.id).update!(custom_role: custom_role)
    user
  end

  def context_for(user, in_account: account)
    { user: user, account: in_account,
      account_user: AccountUser.find_by(account_id: in_account.id, user_id: user&.id) }
  end

  def ticket_for(reporter, in_account: account)
    PlatformSupport::Ticket.create!(account: in_account, account_name_at_creation: in_account.name,
                                    reporter: reporter, reporter_name: reporter.available_name,
                                    subject: "Raised by #{reporter.id}")
  end

  def resolved_for(user, in_account: account)
    described_class::Scope.new(context_for(user, in_account: in_account), PlatformSupport::Ticket.all).resolve
  end

  describe 'the scope applies the account predicate itself' do
    it 'never reaches another account, even when handed the unscoped relation' do
      mine = ticket_for(administrator)
      theirs = ticket_for(create(:user, account: other_account, role: :administrator), in_account: other_account)

      expect(resolved_for(administrator)).to eq([mine])
      expect(resolved_for(administrator)).not_to include(theirs)
    end

    it 'produces SQL carrying the account id without the caller supplying one' do
      expect(resolved_for(administrator).to_sql).to include("\"account_id\" = #{account.id}")
    end
  end

  describe 'D-1 visibility' do
    it 'shows an administrator every ticket of their account, whoever reported it' do
      first = ticket_for(administrator)
      second = ticket_for(agent)

      expect(resolved_for(administrator)).to contain_exactly(first, second)
    end

    it 'shows an agent only the tickets they reported themselves' do
      theirs = ticket_for(agent)
      ticket_for(second_agent)
      ticket_for(administrator)

      expect(resolved_for(agent)).to eq([theirs])
    end

    it 'treats a custom-role holder exactly as an agent' do
      theirs = ticket_for(custom_role_holder)
      ticket_for(administrator)

      expect(resolved_for(custom_role_holder)).to eq([theirs])
    end

    it 'adds no permission string to CustomRole, so no custom role can widen this' do
      expect(CustomRole::PERMISSIONS.grep(/platform/)).to be_empty
    end
  end

  describe 'failing closed' do
    it 'resolves to nothing without an account' do
      ticket_for(administrator)
      scope = described_class::Scope.new({ user: administrator, account: nil, account_user: nil },
                                         PlatformSupport::Ticket.all)

      expect(scope.resolve).to be_empty
    end

    it 'resolves to nothing for a user with no membership of the account' do
      ticket_for(administrator)
      outsider = create(:user, account: other_account, role: :administrator)

      expect(resolved_for(outsider)).to be_empty
    end

    it 'resolves to nothing with no authenticated user' do
      ticket_for(administrator)

      expect(resolved_for(nil)).to be_empty
    end

    it 'resolves to nothing for a role it does not recognise' do
      ticket_for(administrator)
      membership = AccountUser.find_by(account_id: account.id, user_id: administrator.id)
      allow(membership).to receive(:role).and_return('auditor')
      scope = described_class::Scope.new({ user: administrator, account: account, account_user: membership },
                                         PlatformSupport::Ticket.all)

      expect(scope.resolve).to be_empty
    end
  end

  describe 'the actions' do
    it 'lets any member list and open a ticket' do
      [administrator, agent, custom_role_holder].each do |user|
        expect(policy.new(context_for(user), PlatformSupport::Ticket)).to be_index
        expect(policy.new(context_for(user), PlatformSupport::Ticket)).to be_create
      end
    end

    it 'answers show and update from the scope, so visibility has one definition' do
      mine = ticket_for(agent)
      theirs = ticket_for(second_agent)

      expect(policy.new(context_for(agent), mine)).to be_show
      expect(policy.new(context_for(agent), mine)).to be_update
      expect(policy.new(context_for(agent), theirs)).not_to be_show
      expect(policy.new(context_for(agent), theirs)).not_to be_update
    end

    it 'never permits destroy: a ticket is closed, not deleted' do
      expect(policy.new(context_for(administrator), ticket_for(administrator))).not_to be_destroy
    end
  end

  it 'cannot read an orphaned ticket once the account is deleted' do
    ticket = ticket_for(administrator)
    deleted_account_id = account.id
    Account.where(id: deleted_account_id).delete_all

    expect(ticket.reload.account_id).to be_nil
    expect(PlatformSupport::Ticket.where(account_id: deleted_account_id)).to be_empty
  end
end
