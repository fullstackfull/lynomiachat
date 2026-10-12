require 'rails_helper'

# The authorization contract of the notification feed, asserted on the object that owns it
# (docs/product-refinement/11-notifications-and-navigation.md).
#
# The four properties Product Refinement workstream E requires:
#
#   1. a normal Conversation notification still behaves exactly as before;
#   2. every actor type the allow-list names is actually authorizable;
#   3. an actor type nobody authorized does NOT pass -- for any member, administrator included;
#   4. nothing leaks across accounts.
RSpec.describe Notifications::ConversationVisibility do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }

  def visibility(user, for_account: account)
    described_class.for(account: for_account, user: user)
  end

  def notification(user, actor, in_account: account)
    user.notifications.create!(account: in_account, primary_actor: actor, notification_type: 'conversation_assignment')
  end

  before do
    account.enable_features!('custom_roles')
    create(:inbox_member, inbox: inbox, user: agent)
  end

  # ---- 1. The Conversation path is unchanged
  describe 'a notification about a conversation' do
    let(:reachable) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent) }
    let(:unreachable) { create(:conversation, account: account, inbox: create(:inbox, account: account), contact: contact) }

    it 'is shown to a member who can reach the conversation' do
      row = notification(agent, reachable)

      expect(visibility(agent).permits?(row)).to be true
      expect(visibility(agent).narrow(agent.notifications)).to include(row)
    end

    it 'is hidden from a member who cannot reach the conversation' do
      row = notification(agent, unreachable)

      expect(visibility(agent).permits?(row)).to be false
      expect(visibility(agent).narrow(agent.notifications)).not_to include(row)
    end

    it 'is shown to an administrator, who is unrestricted' do
      row = notification(administrator, unreachable)

      expect(visibility(administrator).unrestricted?).to be true
      expect(visibility(administrator).permits?(row)).to be true
      expect(visibility(administrator).narrow(administrator.notifications)).to include(row)
    end

    # The row is never written or deleted: access removed means hidden, access restored means visible again.
    it 'comes back when access is restored, from the same untouched row' do
      row = notification(agent, unreachable)
      expect(visibility(agent).permits?(row)).to be false

      create(:inbox_member, inbox: unreachable.inbox, user: agent)

      expect(visibility(agent.reload).permits?(row.reload)).to be true
    end
  end

  # ---- 2. Every allowed type is authorizable, and the list cannot widen by accident
  describe 'the allow-list' do
    it 'names only the primary-actor types this product declares' do
      expect(described_class::VISIBLE_ACTOR_TYPES).to eq(Notification::PRIMARY_ACTORS)
    end

    # Each entry must have a rule that can actually say yes. A type added to the list without one would make
    # this fail rather than quietly become visible-but-unauthorizable.
    it 'can answer yes for every type it names' do
      expect(described_class::VISIBLE_ACTOR_TYPES).to all(eq('Conversation'))

      row = notification(agent, create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent))
      expect(visibility(agent).permits?(row)).to be true
    end
  end

  # ---- 3. Fail-closed on an actor type nobody authorized
  describe 'a notification whose primary actor is not an authorized type' do
    let(:row) { notification(agent, contact) }

    it 'is refused for a narrowed member' do
      membership = account.account_users.find_by(user_id: agent.id)
      membership.update!(custom_role: create(:custom_role, account: account, permissions: ['contact_manage']), role: :agent)

      expect(visibility(agent.reload).permits?(row)).to be false
      expect(visibility(agent.reload).narrow(agent.notifications)).not_to include(row)
    end

    it 'is refused for a plain agent' do
      expect(visibility(agent).permits?(row)).to be false
      expect(visibility(agent).narrow(agent.notifications)).not_to include(row)
    end

    # The one that matters: "unrestricted" is about which conversations a member may reach, never about which
    # kinds of thing they may be told about.
    it 'is refused for an administrator, who is otherwise unrestricted' do
      admin_row = notification(administrator, contact)

      expect(visibility(administrator).unrestricted?).to be true
      expect(visibility(administrator).permits?(admin_row)).to be false
      expect(visibility(administrator).narrow(administrator.notifications)).not_to include(admin_row)
    end

    # Historical rows: Message still declares `has_many :notifications, as: :primary_actor`, and such a row is
    # about a conversation but does not say which, so it cannot be authorized and is not shown.
    it 'refuses a historical Message row, which cannot be authorized from the notification' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent)
      message = create(:message, account: account, inbox: inbox, conversation: conversation)
      row = notification(agent, message)

      expect(visibility(agent).permits?(row)).to be false
      expect(visibility(agent).narrow(agent.notifications)).not_to include(row)
    end
  end

  # ---- 4. No cross-account leak
  describe 'across accounts' do
    let(:other_inbox) { create(:inbox, account: other_account) }
    let(:other_contact) { create(:contact, account: other_account) }
    let(:other_conversation) do
      create(:conversation, account: other_account, inbox: other_inbox, contact: other_contact)
    end

    before { create(:account_user, account: other_account, user: administrator, role: :administrator) }

    # Asked about another account's notification, an administrator of THIS account is told no. Without the
    # account check this would be yes: ConversationPolicy#show? short-circuits for an administrator and does
    # not look at which account the conversation belongs to.
    it 'refuses a notification belonging to another account' do
      row = notification(administrator, other_conversation, in_account: other_account)

      expect(visibility(administrator, for_account: account).permits?(row)).to be false
    end

    it 'still permits it when asked about the account it belongs to' do
      row = notification(administrator, other_conversation, in_account: other_account)

      expect(visibility(administrator, for_account: other_account).permits?(row)).to be true
    end

    it 'excludes another account\'s rows when narrowing for a restricted member' do
      create(:account_user, account: other_account, user: agent, role: :agent)
      mine = notification(agent, create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent))
      theirs = notification(agent, other_conversation, in_account: other_account)

      narrowed = visibility(agent.reload).narrow(agent.notifications)

      expect(narrowed).to include(mine)
      expect(narrowed).not_to include(theirs)
    end
  end
end
