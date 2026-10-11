require 'rails_helper'

# C: a named permission set is an account-defined list of capability identifiers drawn from a closed vocabulary
# (docs/p-final/clean-room/specs/C-account-role-permissions.md §2, §3, §6).
RSpec.describe CustomRole do
  let(:account) { create(:account) }

  describe 'the closed vocabulary' do
    # One identifier per example rather than the whole list at once: a single rejected identifier would otherwise
    # hide behind the others being accepted, and the vocabulary is the contract the client's
    # app/javascript/dashboard/constants/permissions.js publishes.
    it 'accepts every identifier the product defines, on its own' do
      described_class::PERMISSIONS.each do |permission|
        role = described_class.new(account: account, name: "Only #{permission}", permissions: [permission])

        expect(role).to be_valid, "#{permission} was refused: #{role.errors.full_messages.join(', ')}"
      end
    end

    it 'accepts all of them together' do
      role = described_class.create!(account: account, name: 'Everything', permissions: described_class::PERMISSIONS)

      expect(role.reload.permissions).to match_array(described_class::PERMISSIONS)
    end

    # The client no longer offers this one, but roles created before that change still carry it. Dropping it from
    # the validation would make those existing rows unsaveable, which is why it stays acceptable input.
    it 'still accepts the retired knowledge_base_manage' do
      role = described_class.create!(account: account, name: 'Docs reader', permissions: %w[knowledge_base_manage])

      expect(described_class::PERMISSIONS).to include('knowledge_base_manage')
      expect(role.reload.permissions).to eq(%w[knowledge_base_manage])
    end

    it 'refuses an identifier it does not define and stores nothing' do
      role = described_class.new(account: account, name: 'Invented', permissions: %w[contact_manage billing_manage])

      expect(role).not_to be_valid
      expect(role.errors[:permissions].join).to include('billing_manage')
      expect { role.save }.not_to change(described_class, :count)
    end

    # The whole list is refused, not filtered down to the known part: an account must not end up with a set that
    # quietly grants less than the administrator asked for.
    it 'does not keep the known identifiers of a partly unknown list' do
      described_class.create(account: account, name: 'Invented', permissions: %w[contact_manage billing_manage])

      expect(account.custom_roles).to be_empty
    end

    # One error naming every unknown value, so a client sending two typos learns about both in one round trip.
    it 'names every unknown identifier in a single error' do
      role = described_class.new(account: account, name: 'Typos', permissions: %w[zzz_manage aaa_manage])
      role.validate

      expect(role.errors[:permissions].size).to eq(1)
      expect(role.errors[:permissions].first).to include('aaa_manage, zzz_manage')
    end
  end

  describe 'validations' do
    it 'refuses a set with no name' do
      role = described_class.new(account: account, permissions: %w[contact_manage])

      expect(role).not_to be_valid
      expect(role.errors.attribute_names).to include(:name)
    end

    # A set that grants nothing is a set somebody will later wonder about, and the client will not submit one
    # either (CustomRoleModal.vue), so the server says the same thing.
    it 'refuses a set that grants nothing' do
      role = described_class.new(account: account, name: 'Empty', permissions: [])

      expect(role).not_to be_valid
      expect(role.errors.attribute_names).to include(:permissions)
    end

    it 'refuses a set whose permission list was never given' do
      role = described_class.new(account: account, name: 'Unset')

      expect(role).not_to be_valid
      expect(role.errors.attribute_names).to include(:permissions)
    end
  end

  describe 'deleting a set that is in use' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:membership) { account.account_users.find_by(user: agent) }
    let(:role) { create(:custom_role, account: account, name: 'Support lead', permissions: %w[support_ticket_manage]) }

    before { membership.update!(custom_role: role) }

    # Detach, never destroy: `has_many :account_users, dependent: :destroy` here would delete the person along
    # with the set, which §6 says is never acceptable.
    it 'detaches the membership instead of destroying it' do
      expect { role.destroy! }.not_to change(AccountUser, :count)

      expect(membership.reload).to be_persisted
      expect(membership.custom_role_id).to be_nil
    end

    it 'leaves the membership with its built-in role and that role’s capabilities' do
      role.destroy!

      expect(membership.reload.role).to eq('agent')
      expect(membership.permissions).to eq(%w[agent])
    end

    it 'keeps the user and the account membership itself' do
      role.destroy!

      expect(account.users.reload).to include(agent)
    end

    # The detachment has to run through the membership, not through `update_all`. Chatwoot declares
    # `custom_role_id` a column that changes which conversations a member can see, and invalidates their cached
    # filtered unread counts whenever it moves (app/models/account_user.rb:85-87). A `dependent: :nullify`
    # skips that callback, so deleting a set would leave its holders counting conversations under the
    # visibility it used to grant -- while the identical change on the agent endpoint invalidates correctly.
    it 'tells the unread-count cache that this member can now see something different' do
      invalidator = instance_double(Conversations::UnreadCounts::FilteredCountInvalidator)
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).and_return(invalidator)
      allow(invalidator).to receive(:user_visibility_changed!).and_return(true)

      role.destroy!

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: agent.id).at_least(:once)
    end
  end
end
