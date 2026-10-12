require 'rails_helper'

# The Inbox/Team ceiling, in the two shapes it is now offered in -- and, above all, the proof that they agree
# with each other AND with the policy.
#
# This file exists because the ceiling became a relation as well as a record predicate. A relation that answers
# differently from the policy would be a second interpretation of inbox-and-team visibility, which is the exact
# failure the closure was told to avoid. The equivalence example below is therefore the load-bearing test here:
# it walks every combination of administrator, inbox membership, team membership and team presence, and asserts
# the relation and `ConversationPolicy#show?` agree on every one.
RSpec.describe Conversations::AccessCeiling do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:other_team) { create(:team, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }

  def ceiling_for(user)
    described_class.for(account_user: account.account_users.find_by(user: user), user: user, account: account)
  end

  def policy_allows?(user, conversation)
    ConversationPolicy.new(
      { user: user, account: account, account_user: account.account_users.find_by(user: user) }, conversation
    ).show?
  end

  def conversation_in(target_inbox, team_record: nil)
    if team_record
      create(:conversation, :with_team, account: account, inbox: target_inbox, contact: contact, team: team_record)
    else
      create(:conversation, account: account, inbox: target_inbox, contact: contact)
    end
  end

  describe 'who the ceiling does not restrict' do
    it 'does not restrict an administrator' do
      expect(ceiling_for(administrator)).to be_unrestricted
    end

    it 'restricts an ordinary agent' do
      expect(ceiling_for(agent)).not_to be_unrestricted
    end

    it 'does not restrict an agent bot, which is not a membership' do
      bot = create(:agent_bot)
      ceiling = described_class.for(account_user: nil, user: bot, account: account)

      expect(ceiling).to be_unrestricted
    end
  end

  describe 'the record answer' do
    it 'grants on inbox membership' do
      create(:inbox_member, inbox: inbox, user: agent)

      expect(ceiling_for(agent).agent_can_view?(conversation_in(inbox))).to be(true)
    end

    it 'grants on team membership, which needs no inbox membership' do
      create(:team_member, team: team, user: agent)

      expect(ceiling_for(agent).agent_can_view?(conversation_in(other_inbox, team_record: team))).to be(true)
    end

    it 'refuses a conversation whose team the agent does not belong to' do
      create(:team_member, team: team, user: agent)

      expect(ceiling_for(agent).agent_can_view?(conversation_in(other_inbox, team_record: other_team))).to be(false)
    end

    it 'refuses when the agent has neither' do
      expect(ceiling_for(agent).agent_can_view?(conversation_in(inbox))).to be(false)
    end

    # The semantic most likely to be assumed wrong: being the assignee is not access. ConversationPolicy
    # defines `assigned_to_user?` and never calls it from `show?`, and this preserves that exactly.
    it 'refuses the assignee of a conversation in an inbox they do not belong to' do
      conversation = conversation_in(inbox)
      conversation.update!(assignee: agent)

      expect(ceiling_for(agent).agent_can_view?(conversation.reload)).to be(false)
    end
  end

  describe 'the relation answer' do
    it 'returns every conversation in the account for an administrator' do
      mine = conversation_in(inbox)
      theirs = conversation_in(other_inbox)

      expect(ceiling_for(administrator).narrow(account.conversations)).to contain_exactly(mine, theirs)
    end

    it 'returns the inbox-reachable and team-reachable ones, and nothing else' do
      create(:inbox_member, inbox: inbox, user: agent)
      create(:team_member, team: team, user: agent)

      by_inbox = conversation_in(inbox)
      by_team = conversation_in(other_inbox, team_record: team)
      unreachable = conversation_in(other_inbox)
      wrong_team = conversation_in(other_inbox, team_record: other_team)

      expect(ceiling_for(agent).narrow(account.conversations)).to contain_exactly(by_inbox, by_team)
      expect(ceiling_for(agent).narrow(account.conversations)).not_to include(unreachable, wrong_team)
    end

    it 'returns nothing for an agent with no membership at all' do
      conversation_in(inbox)

      expect(ceiling_for(agent).narrow(account.conversations)).to be_empty
    end

    it 'never reaches another account, even for an administrator' do
      foreign = create(:conversation, account: other_account, inbox: create(:inbox, account: other_account),
                                      contact: create(:contact, account: other_account))

      expect(ceiling_for(administrator).narrow(account.conversations)).not_to include(foreign)
    end
  end

  # THE ARCHITECTURAL GUARANTEE. One rule, two shapes, and the policy is the authority on the record side --
  # so the relation must agree with it everywhere. The agents here hold no permission set, which keeps
  # `Conversations::CapabilityScope` at :base and isolates the ceiling as the only thing under test.
  describe 'the relation and ConversationPolicy#show? agreeing' do
    it 'gives the same answer for every combination of inbox, team and role' do
      create(:inbox_member, inbox: inbox, user: agent)
      create(:team_member, team: team, user: agent)

      cases = {
        'in my inbox, no team' => conversation_in(inbox),
        'in my inbox, my team' => conversation_in(inbox, team_record: team),
        'in my inbox, another team' => conversation_in(inbox, team_record: other_team),
        'another inbox, my team' => conversation_in(other_inbox, team_record: team),
        'another inbox, another team' => conversation_in(other_inbox, team_record: other_team),
        'another inbox, no team' => conversation_in(other_inbox)
      }

      [agent, administrator].each do |user|
        listed = ceiling_for(user).narrow(account.conversations).to_a

        cases.each do |label, conversation|
          expect(listed.include?(conversation)).to eq(policy_allows?(user, conversation)),
                                                   "#{user.id == agent.id ? 'agent' : 'administrator'} disagreed on '#{label}': " \
                                                   "relation=#{listed.include?(conversation)} policy=#{policy_allows?(user, conversation)}"
        end
      end
    end
  end
end
