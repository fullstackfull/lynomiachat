require 'rails_helper'

# DECISIONS 1 and 2, asserted where they are decided.
#
# This file covers the rule itself -- the four modes, the combinations, the grandfather clause and the
# entitlement upper bound. spec/requests/conversation_capabilities_spec.rb covers the same rule through the
# HTTP surfaces, because a rule that holds in a unit and not on the endpoint is not enforcement.
RSpec.describe Conversations::CapabilityScope do
  let(:account) { create(:account) }
  # Three conversations, one of each shape the capabilities distinguish.
  let!(:mine) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent) }
  let!(:unassigned) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: nil) }
  let!(:theirs) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: other_agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:membership) { account.account_users.find_by(user: agent) }

  let(:contact) { create(:contact, account: account) }

  before do
    account.enable_features!('custom_roles')
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_member, inbox: inbox, user: other_agent)
  end

  def attach(*permissions)
    membership.update!(custom_role: create(:custom_role, account: account, permissions: permissions), role: :agent)
    membership.reload
  end

  def scope_for(account_user = membership)
    described_class.for(account_user)
  end

  def narrowed
    scope_for.narrow(account.conversations, user: agent)
  end

  describe 'the four modes' do
    it 'is :base for a membership with no set attached' do
      expect(scope_for.mode).to eq(:base)
      expect(narrowed).to contain_exactly(mine, unassigned, theirs)
    end

    it 'is :base for an administrator, whose reach is the role column rather than a capability list' do
      admin = create(:user, account: account, role: :administrator)

      expect(scope_for(account.account_users.find_by(user: admin)).mode).to eq(:base)
    end

    it 'is :base for conversation_manage' do
      attach('conversation_manage')

      expect(scope_for.mode).to eq(:base)
      expect(narrowed).to contain_exactly(mine, unassigned, theirs)
    end

    it 'is :unassigned_and_mine for conversation_unassigned_manage' do
      attach('conversation_unassigned_manage')

      expect(scope_for.mode).to eq(:unassigned_and_mine)
      expect(narrowed).to contain_exactly(mine, unassigned)
    end

    it 'is :mine for conversation_participating_manage' do
      attach('conversation_participating_manage')

      expect(scope_for.mode).to eq(:mine)
      expect(narrowed).to contain_exactly(mine)
    end

    it 'is :none for a new set that names none of the three' do
      attach('contact_manage')

      expect(scope_for.mode).to eq(:none)
      expect(narrowed).to be_empty
    end
  end

  describe 'combinations, where the widest wins' do
    it 'treats manage plus participating as manage' do
      attach('conversation_manage', 'conversation_participating_manage')

      expect(narrowed).to contain_exactly(mine, unassigned, theirs)
    end

    it 'treats unassigned plus participating as unassigned and mine' do
      attach('conversation_unassigned_manage', 'conversation_participating_manage')

      expect(narrowed).to contain_exactly(mine, unassigned)
    end

    it 'ignores capabilities from other families' do
      attach('conversation_participating_manage', 'contact_manage', 'commerce_order_manage')

      expect(narrowed).to contain_exactly(mine)
    end
  end

  describe 'what unassigned means' do
    # The product's own definition: no human assignee AND no bot assignee (app/models/conversation.rb:89). A
    # bot-assigned conversation is not unassigned, and the unread counter already excludes it, so the two agree.
    it 'does not count a bot-assigned conversation as unassigned' do
      bot = create(:agent_bot)
      bot_assigned = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: nil)
      bot_assigned.update!(ai_assignee: bot)
      attach('conversation_unassigned_manage')

      expect(narrowed).to contain_exactly(mine, unassigned)
      expect(scope_for.permits?(bot_assigned.reload, user: agent)).to be(false)
    end
  end

  describe 'the record answer agreeing with the relation' do
    it 'permits exactly the conversations the relation returns, for every mode' do
      [%w[conversation_manage], %w[conversation_unassigned_manage], %w[conversation_participating_manage],
       %w[contact_manage]].each do |permissions|
        attach(*permissions)
        listed = narrowed.to_a

        [mine, unassigned, theirs].each do |conversation|
          expect(scope_for.permits?(conversation, user: agent)).to eq(listed.include?(conversation)),
                                                                   "#{permissions.first} disagreed about #{conversation.id}"
        end
      end
    end

    it 'never treats an unassigned conversation as the holder own' do
      attach('conversation_participating_manage')

      expect(scope_for.permits?(unassigned, user: agent)).to be(false)
    end
  end

  describe 'existing sets, which must not lose access' do
    # The grandfather clause. A set that predates this release and names none of the three keeps working,
    # because the capability was not enforcing when its administrator chose it.
    it 'leaves a grandfathered set unrestricted' do
      attach('contact_manage')
      membership.custom_role.update_column(:conversation_scope_enforced, false) # rubocop:disable Rails/SkipsModelValidations

      expect(scope_for(membership.reload).mode).to eq(:base)
      expect(narrowed).to contain_exactly(mine, unassigned, theirs)
    end

    it 'enforces a grandfathered set the moment an operator edits its conversation capabilities' do
      attach('contact_manage')
      role = membership.custom_role
      role.update_column(:conversation_scope_enforced, false) # rubocop:disable Rails/SkipsModelValidations

      role.update!(permissions: %w[contact_manage conversation_participating_manage])

      expect(role.reload.conversation_scope_enforced).to be(true)
      expect(scope_for(membership.reload).mode).to eq(:mine)
    end

    it 'leaves a grandfathered set alone when an edit says nothing about conversations' do
      attach('contact_manage')
      role = membership.custom_role
      role.update_column(:conversation_scope_enforced, false) # rubocop:disable Rails/SkipsModelValidations

      role.update!(permissions: %w[contact_manage commerce_order_manage])

      expect(role.reload.conversation_scope_enforced).to be(false)
      expect(scope_for(membership.reload).mode).to eq(:base)
    end

    it 'does not treat reordering the same capabilities as an edit' do
      attach('conversation_participating_manage', 'contact_manage')
      role = membership.custom_role
      role.update_column(:conversation_scope_enforced, false) # rubocop:disable Rails/SkipsModelValidations

      role.update!(permissions: %w[contact_manage conversation_participating_manage])

      expect(role.reload.conversation_scope_enforced).to be(false)
    end

    it 'enforces every newly created set' do
      attach('contact_manage')

      expect(membership.custom_role.conversation_scope_enforced).to be(true)
    end
  end

  describe 'the entitlement upper bound (DECISION 2)' do
    before { attach('conversation_participating_manage') }

    it 'narrows while the account is entitled' do
      expect(scope_for.mode).to eq(:mine)
    end

    it 'treats the holder as a plain agent once the entitlement is gone' do
      account.disable_features!('custom_roles')

      expect(scope_for(membership.reload).mode).to eq(:base)
    end

    # The direction that matters: the fallback must be the LEAST privileged compatible behaviour, never a
    # widening into administrator. A membership holding a set is an agent by invariant, so `super` is the agent
    # list, and `administrator?` is the role column, which this never touches.
    it 'does not make the holder an administrator' do
      account.disable_features!('custom_roles')
      reloaded = membership.reload

      expect(reloaded.permissions).not_to include('administrator')
      expect(reloaded.administrator?).to be(false)
      expect(reloaded.agent?).to be(true)
    end

    it 'restores the narrowing when the entitlement returns' do
      account.disable_features!('custom_roles')
      expect(scope_for(membership.reload).mode).to eq(:base)

      account.enable_features!('custom_roles')

      expect(scope_for(membership.reload).mode).to eq(:mine)
    end

    it 'keeps the set and the attachment through the round trip' do
      role_id = membership.custom_role_id
      account.disable_features!('custom_roles')
      account.enable_features!('custom_roles')

      expect(membership.reload.custom_role_id).to eq(role_id)
      expect(CustomRole.exists?(role_id)).to be(true)
    end

    # THE OPERATOR'S LEVER, asserted through the writer an operator actually goes through rather than through
    # the raw bitmask. `custom_roles` is a capability a Lynomia plan sells (it is in
    # BillingPlan.assignable_features), so `write_features!` routes it through `reconcile_feature`: the account
    # here has no subscription, so asking for anything other than the plan's answer -- and no plan means no --
    # records a real, audited override rather than a bare flag write. Either way the effective entitlement is
    # what this scope reads, which is the property that matters.
    #
    # The commercial wiring itself is asserted in spec/models/billing_plan_custom_roles_spec.rb.
    it 'follows the operator writer that actually controls this capability' do
      grant = Billing::OverrideGrant.new(account, actor: create(:super_admin))

      grant.write_features!({ 'custom_roles' => false }, reason: 'downgrade')
      expect(scope_for(membership.reload).mode).to eq(:base)

      grant.write_features!({ 'custom_roles' => true }, reason: 'reinstated')
      expect(scope_for(membership.reload).mode).to eq(:mine)
    end
  end

  # WHERE TENANT ISOLATION ACTUALLY LIVES, so the next reader does not look for it in the wrong object.
  #
  # `narrow` only ever intersects the relation it is handed, so it cannot reach outside the account scope its
  # caller already applied -- which is what the first example asserts. `permits?` is the other half of the same
  # rule and answers ONLY the capability question: it is composed with `super` in Custom::ConversationPolicy,
  # and the account check is `super`'s, as it is for every other policy in this product. So `permits?` says
  # true for a foreign UNASSIGNED conversation under :unassigned_and_mine -- honestly, because unassigned is
  # what the capability is about -- and the foreign conversation is refused one layer up. The composed answer,
  # which is the one an attacker actually meets, is asserted over HTTP in
  # spec/requests/conversation_capabilities_spec.rb.
  describe 'tenant isolation' do
    let(:foreign) do
      other = create(:account)
      create(:conversation, account: other, inbox: create(:inbox, account: other),
                            contact: create(:contact, account: other), assignee: nil)
    end

    it 'returns no conversation of another account in any mode' do
      %w[conversation_manage conversation_unassigned_manage conversation_participating_manage contact_manage].each do |capability|
        attach(capability)

        expect(narrowed).not_to include(foreign)
      end
    end
  end
end
