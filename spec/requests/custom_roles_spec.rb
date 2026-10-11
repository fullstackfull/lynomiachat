require 'rails_helper'

# Package C: named permission sets (docs/p-final/clean-room/specs/C-account-role-permissions.md).
#
# The risk this package carries is privilege escalation -- a capability that lets its holder grant itself more --
# so the authorization examples are the load-bearing ones, and §5's two isolation rules (a set is reachable only
# from its own account, and a membership may hold only its own account's set) are asserted from both sides.
RSpec.describe 'Custom roles API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:role_holder) { create(:user, account: account, role: :agent) }
  let(:membership) { account.account_users.find_by(user: agent) }
  let(:holder_membership) { account.account_users.find_by(user: role_holder) }

  before { account.enable_features!('custom_roles') }

  # Every request in this file is an authenticated call against the same account, so the path prefix and the
  # token headers are the only repetition worth hiding.
  def as(user, verb, path, params = {})
    public_send(verb, "/api/v1/accounts/#{account.id}/#{path}", params: params, headers: user.create_new_auth_token, as: :json)
  end

  describe 'C-1 creating a set' do
    it 'returns the created set with its identifier, name, description and permissions' do
      as(admin, :post, 'custom_roles',
         { custom_role: { name: 'Order desk', description: 'Handles store orders',
                          permissions: %w[conversation_manage commerce_order_manage] } })

      expect(response).to have_http_status(:created)
      # An exact comparison, not `include`: these four keys are the whole of what the roles table and the agent
      # pages read, and an extra key here would be a contract nobody asked for.
      expect(response.parsed_body).to eq(
        'id' => account.custom_roles.last.id,
        'name' => 'Order desk',
        'description' => 'Handles store orders',
        'permissions' => %w[conversation_manage commerce_order_manage]
      )
    end

    it 'accepts the retired knowledge_base_manage, so a set created before the client dropped it stays saveable' do
      as(admin, :post, 'custom_roles', { custom_role: { name: 'Docs reader', permissions: %w[knowledge_base_manage] } })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['permissions']).to eq(%w[knowledge_base_manage])
    end
  end

  describe 'C-2 listing, reading, renaming and deleting' do
    let!(:order_desk) { create(:custom_role, account: account, name: 'Order desk', permissions: %w[commerce_order_manage]) }
    let!(:analyst) { create(:custom_role, account: account, name: 'Analyst', permissions: %w[report_manage]) }
    let!(:theirs) { create(:custom_role, account: other_account, name: 'Theirs', permissions: %w[contact_manage]) }

    it "lists only this account's sets" do
      as(admin, :get, 'custom_roles')

      expect(response).to have_http_status(:success)
      # A bare array, because the store commits the response body straight into its records.
      expect(response.parsed_body.pluck('id')).to eq([analyst.id, order_desk.id])
      expect(response.parsed_body.pluck('id')).not_to include(theirs.id)
    end

    it 'reads one' do
      as(admin, :get, "custom_roles/#{order_desk.id}")

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('id' => order_desk.id, 'name' => 'Order desk',
                                              'permissions' => %w[commerce_order_manage])
    end

    it 'renames one without touching its permissions' do
      as(admin, :patch, "custom_roles/#{order_desk.id}", { custom_role: { name: 'Order management' } })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('name' => 'Order management', 'permissions' => %w[commerce_order_manage])
      expect(order_desk.reload.permissions).to eq(%w[commerce_order_manage])
    end

    it 'deletes one, leaving the other' do
      expect { as(admin, :delete, "custom_roles/#{analyst.id}") }.to change(account.custom_roles, :count).by(-1)

      expect(response).to have_http_status(:success)
      expect(account.custom_roles.reload).to contain_exactly(order_desk)
    end
  end

  describe 'C-3 an unknown permission' do
    it 'is refused with 422 and creates nothing' do
      expect do
        as(admin, :post, 'custom_roles', { custom_role: { name: 'Invented', permissions: %w[contact_manage billing_manage] } })
      end.not_to change(CustomRole, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      # The message names the offending value, because the client shows it verbatim next to the field.
      expect(response.parsed_body['message']).to include('billing_manage')
    end

    it 'is refused on an update too, leaving the stored list alone' do
      set = create(:custom_role, account: account, name: 'Order desk', permissions: %w[commerce_order_manage])

      as(admin, :patch, "custom_roles/#{set.id}", { custom_role: { permissions: %w[billing_manage] } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(set.reload.permissions).to eq(%w[commerce_order_manage])
    end
  end

  describe 'C-4 a nameless or empty set' do
    it 'refuses a set with no name and says which field is wrong' do
      expect do
        as(admin, :post, 'custom_roles', { custom_role: { permissions: %w[report_manage] } })
      end.not_to change(CustomRole, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to include('name')
    end

    it 'refuses a set that grants nothing' do
      expect do
        as(admin, :post, 'custom_roles', { custom_role: { name: 'Empty', permissions: [] } })
      end.not_to change(CustomRole, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to include('permissions')
    end
  end

  describe 'C-5 only administrators may manage sets' do
    let!(:existing) { create(:custom_role, account: account, name: 'Order desk', permissions: %w[commerce_order_manage]) }

    # Every capability the product defines, attached to an ordinary agent: if holding a capability could open
    # these endpoints, this is the member it would open them for.
    before { holder_membership.update!(custom_role: create(:custom_role, account: account, permissions: CustomRole::PERMISSIONS)) }

    { 'an agent' => :agent, 'a member holding every capability the product defines' => :role_holder }.each do |description, who|
      it "refuses #{description} on create, update and delete" do
        caller_user = public_send(who)

        expect do
          as(caller_user, :post, 'custom_roles', { custom_role: { name: 'Mine', permissions: %w[report_manage] } })
        end.not_to change(CustomRole, :count)
        expect(response).to have_http_status(:unauthorized)

        as(caller_user, :patch, "custom_roles/#{existing.id}", { custom_role: { name: 'Renamed' } })
        expect(response).to have_http_status(:unauthorized)

        expect { as(caller_user, :delete, "custom_roles/#{existing.id}") }.not_to change(CustomRole, :count)
        expect(response).to have_http_status(:unauthorized)
        expect(existing.reload.name).to eq('Order desk')
      end

      it "refuses #{description} on list and read, because only administrators may read the account's sets" do
        caller_user = public_send(who)

        as(caller_user, :get, 'custom_roles')
        expect(response).to have_http_status(:unauthorized)

        as(caller_user, :get, "custom_roles/#{existing.id}")
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'C-6 [isolation] sets are per account' do
    let!(:mine) { create(:custom_role, account: account, name: 'Mine', permissions: %w[contact_manage]) }
    let!(:theirs) { create(:custom_role, account: other_account, name: 'Theirs', permissions: %w[report_manage]) }

    it "excludes the other account's set from the list" do
      as(admin, :get, 'custom_roles')

      expect(response.parsed_body.pluck('id')).to eq([mine.id])
    end

    # 404 rather than 403 on every one of the three: a 403 would confirm that the id exists in some other
    # account, which is itself a leak.
    it 'answers 404 on read, update and delete, and leaves it unchanged' do
      as(admin, :get, "custom_roles/#{theirs.id}")
      expect(response).to have_http_status(:not_found)

      as(admin, :patch, "custom_roles/#{theirs.id}", { custom_role: { name: 'Taken over', permissions: %w[conversation_manage] } })
      expect(response).to have_http_status(:not_found)

      expect { as(admin, :delete, "custom_roles/#{theirs.id}") }.not_to change(CustomRole, :count)
      expect(response).to have_http_status(:not_found)

      expect(theirs.reload).to have_attributes(name: 'Theirs', permissions: %w[report_manage])
    end
  end

  describe 'C-7 attaching a set when a member is invited' do
    let!(:order_desk) { create(:custom_role, account: account, name: 'Order desk', permissions: %w[commerce_order_manage]) }
    let(:invited) { account.users.from_email('new-hire@example.com') }

    it 'attaches the set to the new membership' do
      as(admin, :post, 'agents',
         { agent: { name: 'New hire', email: 'new-hire@example.com', role: 'agent', custom_role_id: order_desk.id } })

      expect(response).to have_http_status(:success)
      # The invite page reads the set back off this response (settings/agents/AddAgent.vue), so it is part of the
      # contract and not only the stored row.
      expect(response.parsed_body['custom_role_id']).to eq(order_desk.id)
      new_membership = account.account_users.find_by(user: invited)
      expect(new_membership.custom_role_id).to eq(order_desk.id)
      # What the set grants plus the marker saying it has one, and nothing else: an invited role-holder is not
      # also an agent for permission purposes.
      expect(new_membership.permissions).to contain_exactly('commerce_order_manage', 'custom_role')
    end

    it 'invites without a set when the request does not name one' do
      as(admin, :post, 'agents', { agent: { name: 'Plain hire', email: 'plain-hire@example.com', role: 'agent' } })

      expect(response).to have_http_status(:success)
      expect(account.account_users.find_by(user: account.users.from_email('plain-hire@example.com')).custom_role_id).to be_nil
    end
  end

  describe 'C-8 attaching to and detaching from an existing member' do
    let!(:order_desk) { create(:custom_role, account: account, name: 'Order desk', permissions: %w[commerce_order_manage]) }

    it 'attaches the set and reports it back' do
      as(admin, :patch, "agents/#{agent.id}", { agent: { custom_role_id: order_desk.id } })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['custom_role_id']).to eq(order_desk.id)
      expect(membership.reload.permissions).to contain_exactly('commerce_order_manage', 'custom_role')
    end

    # The detachment is the half upstream cannot do: it applies the membership's attributes with `.compact`,
    # which drops a nil, so an explicit null would be silently ignored and the set would stay attached. Asserting
    # the stored row rather than only the response is the point of this example.
    it 'detaches the set when the client sends an explicit null' do
      membership.update!(custom_role: order_desk)

      as(admin, :patch, "agents/#{agent.id}", { agent: { custom_role_id: nil } })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['custom_role_id']).to be_nil
      expect(membership.reload.custom_role_id).to be_nil
      expect(membership.permissions).to eq(%w[agent])
    end

    # An update that says nothing about the set must leave it alone, which is why the attachment is applied on
    # the key being present rather than on a value being given.
    it 'leaves the set alone when the request does not mention it' do
      membership.update!(custom_role: order_desk)

      as(admin, :patch, "agents/#{agent.id}", { agent: { name: 'Renamed agent' } })

      expect(response).to have_http_status(:success)
      expect(membership.reload.custom_role_id).to eq(order_desk.id)
    end
  end

  describe 'C-9 what the product tells the browser about a membership' do
    let!(:order_desk) do
      create(:custom_role, account: account, name: 'Order desk', permissions: %w[commerce_order_manage contact_manage])
    end

    before { holder_membership.update!(custom_role: order_desk) }

    def profile_membership(user)
      get '/api/v1/profile', headers: user.create_new_auth_token, as: :json
      response.parsed_body['accounts'].find { |entry| entry['id'] == account.id }
    end

    it "states the membership's role and the set's permissions under the names the client reads" do
      payload = profile_membership(role_holder)

      expect(response).to have_http_status(:success)
      expect(payload['role']).to eq('agent')
      expect(payload['permissions']).to contain_exactly('commerce_order_manage', 'contact_manage', 'custom_role')
    end

    # The account switcher reads `account.custom_role.name` with no guard at all, so a membership reporting only
    # the id would make it throw (components-next/sidebar/SidebarAccountSwitcher.vue).
    it "serialises both the set's id and a nested object carrying its name" do
      payload = profile_membership(role_holder)

      expect(payload['custom_role_id']).to eq(order_desk.id)
      expect(payload['custom_role']).to include('id' => order_desk.id, 'name' => 'Order desk')
    end

    it 'reports no set, and the built-in capabilities, for a membership that has none' do
      payload = profile_membership(agent)

      expect(payload['custom_role_id']).to be_nil
      expect(payload['custom_role']).to be_nil
      expect(payload['permissions']).to eq(%w[agent])
    end

    it 'reports the attached set on the agent list the settings page renders' do
      as(admin, :get, 'agents')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.find { |row| row['id'] == role_holder.id }).to include('custom_role_id' => order_desk.id)
    end
  end

  describe 'C-10 each capability gates its own feature' do
    describe 'commerce_order_manage' do
      # Asserted against Commerce::ActionPolicy rather than through the order-action endpoint, because reaching
      # that endpoint also needs a connected store and a live provider adapter, neither of which this capability
      # has anything to do with. The policy is the product's only definition of the rule, and
      # Commerce::OrderActions consults it before any provider call.
      def may?(user, action_type)
        Commerce::ActionPolicy.new(
          { user: user, account: account, account_user: account.account_users.find_by(user: user) }, action_type
        ).perform?
      end

      it 'lets a holder manage an order and refuses an agent without it' do
        holder_membership.update!(custom_role: create(:custom_role, account: account, permissions: %w[commerce_order_manage]))

        expect(may?(role_holder, 'update_order_status')).to be(true)
        expect(may?(agent, 'update_order_status')).to be(false)
      end

      it 'refuses a holder of some other capability' do
        holder_membership.update!(custom_role: create(:custom_role, account: account, permissions: %w[report_manage]))

        expect(may?(role_holder, 'update_order_status')).to be(false)
      end

      # Money leaving the account stays administrator-only, so the capability must not widen into it.
      it 'does not extend to a refund or a cancellation' do
        holder_membership.update!(custom_role: create(:custom_role, account: account, permissions: %w[commerce_order_manage]))

        expect(may?(role_holder, 'refund_full')).to be(false)
        expect(may?(role_holder, 'cancel_order')).to be(false)
      end
    end

    describe 'support_ticket_manage' do
      let!(:assigned_to_the_agent) { create(:support_ticket, account: account, assignee: agent) }
      let!(:somebody_elses) { create(:support_ticket, account: account, assignee: admin) }

      before { account.enable_features!('lynomia_support_tickets') }

      it 'shows a holder every case in the account, and an agent only their own' do
        holder_membership.update!(custom_role: create(:custom_role, account: account, permissions: %w[support_ticket_manage]))

        as(role_holder, :get, 'support/tickets')
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(assigned_to_the_agent.id, somebody_elses.id)

        as(agent, :get, 'support/tickets')
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].pluck('id')).to eq([assigned_to_the_agent.id])
      end

      # A refusal on a case the caller may not see is a 404 through the policy scope, not a 500 and not a silent
      # success that returns the row anyway.
      it "answers 404 when an agent without it reads somebody else's case" do
        as(agent, :get, "support/tickets/#{somebody_elses.id}")

        expect(response).to have_http_status(:not_found)
      end
    end

    describe 'contact_manage' do
      let!(:base_contact) { create(:contact, account: account, name: 'Keeper') }
      let!(:mergee_contact) { create(:contact, account: account, name: 'Duplicate') }

      it 'lets a holder merge two contacts and refuses an agent without it' do
        holder_membership.update!(custom_role: create(:custom_role, account: account, permissions: %w[contact_manage]))
        merge = { base_contact_id: base_contact.id, mergee_contact_id: mergee_contact.id }

        as(agent, :post, 'actions/contact_merge', merge)
        expect(response).to have_http_status(:unauthorized)
        expect(Contact.exists?(mergee_contact.id)).to be(true)

        as(role_holder, :post, 'actions/contact_merge', merge)
        expect(response).to have_http_status(:success)
        expect(Contact.exists?(mergee_contact.id)).to be(false)
      end
    end
  end

  describe 'C-11 an administrator is never narrowed by a set' do
    before { account.account_users.find_by(user: admin).update!(custom_role: create(:custom_role, account: account, permissions: %w[report_manage])) }

    it 'still performs an administrator action the set says nothing about' do
      as(admin, :post, 'agents', { agent: { name: 'New hire', email: 'new-hire@example.com', role: 'agent' } })

      expect(response).to have_http_status(:success)
    end

    # Every administrator check in the product reads the `role` column, not the capability list -- which is why
    # the administrator can still reach these very endpoints while holding a set that grants neither.
    it 'still manages sets' do
      as(admin, :post, 'custom_roles', { custom_role: { name: 'Another', permissions: %w[contact_manage] } })

      expect(response).to have_http_status(:created)
    end
  end

  describe 'C-12 deleting a set deletes nobody' do
    let(:second_admin) { create(:user, account: account, role: :administrator) }
    let(:shared) { create(:custom_role, account: account, name: 'Shared', permissions: %w[contact_manage]) }

    before do
      membership.update!(custom_role: shared)
      account.account_users.find_by(user: second_admin).update!(custom_role: shared)
    end

    it 'keeps both memberships, with their base roles and no set' do
      second_membership = account.account_users.find_by(user: second_admin)

      as(admin, :delete, "custom_roles/#{shared.id}")

      expect(response).to have_http_status(:success)
      # `reload` is the assertion: it raises if the membership went with the set, which §6 says must never
      # happen. The base role is the rest of it -- a deleted set must leave an administrator an administrator.
      expect(membership.reload).to have_attributes(role: 'agent', custom_role_id: nil)
      expect(second_membership.reload).to have_attributes(role: 'administrator', custom_role_id: nil)
      expect(account.users.reload).to include(agent, second_admin)
    end

    it 'deletes nothing the members owned' do
      conversation = create(:conversation, account: account, assignee: agent)

      as(admin, :delete, "custom_roles/#{shared.id}")

      expect(conversation.reload.assignee_id).to eq(agent.id)
    end
  end

  describe 'C-13 changing a set keeps it attached' do
    let(:order_desk) { create(:custom_role, account: account, name: 'Order desk', permissions: %w[commerce_order_manage]) }

    before { membership.update!(custom_role: order_desk) }

    it 'renames it, replaces its permissions, and the member gains the new ones' do
      as(admin, :patch, "custom_roles/#{order_desk.id}",
         { custom_role: { name: 'Support lead', permissions: %w[support_ticket_manage] } })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('name' => 'Support lead', 'permissions' => %w[support_ticket_manage])
      expect(membership.reload.custom_role_id).to eq(order_desk.id)
      expect(membership.permissions).to contain_exactly('support_ticket_manage', 'custom_role')
    end
  end

  describe 'C-14 [isolation] a set cannot be attached across accounts' do
    let!(:theirs) { create(:custom_role, account: other_account, name: 'Theirs', permissions: %w[conversation_manage]) }

    # Nothing in the schema stops this: there is no foreign key on account_users.custom_role_id, so without a
    # check at the request boundary account A would silently inherit whatever account B's administrator put in
    # the set.
    it 'refuses the attach and leaves the membership untouched' do
      as(admin, :patch, "agents/#{agent.id}", { agent: { custom_role_id: theirs.id } })

      expect(response).to have_http_status(:not_found)
      expect(membership.reload.custom_role_id).to be_nil
      expect(membership.permissions).to eq(%w[agent])
    end

    it "does not replace an attached set with another account's" do
      mine = create(:custom_role, account: account, name: 'Mine', permissions: %w[contact_manage])
      membership.update!(custom_role: mine)

      as(admin, :patch, "agents/#{agent.id}", { agent: { custom_role_id: theirs.id } })

      expect(response).to have_http_status(:not_found)
      expect(membership.reload.custom_role_id).to eq(mine.id)
    end

    it 'refuses the invite that carries it, creating no member at all' do
      as(admin, :post, 'agents',
         { agent: { name: 'New hire', email: 'new-hire@example.com', role: 'agent', custom_role_id: theirs.id } })

      expect(response).to have_http_status(:not_found)
      # The check runs before the invite does, so there is no half-made member holding another account's set.
      expect(User.from_email('new-hire@example.com')).to be_nil
      expect(account.users.reload.pluck(:email)).not_to include('new-hire@example.com')
    end
  end

  describe 'C-15 without the account capability' do
    before { account.disable_features!('custom_roles') }

    it 'refuses all five endpoints clearly rather than failing' do
      existing = create(:custom_role, account: account, name: 'Order desk', permissions: %w[commerce_order_manage])
      payload = { custom_role: { name: 'Mine', permissions: %w[report_manage] } }

      [[:get, 'custom_roles'], [:post, 'custom_roles'], [:get, "custom_roles/#{existing.id}"],
       [:patch, "custom_roles/#{existing.id}"], [:delete, "custom_roles/#{existing.id}"]].each do |verb, path|
        as(admin, verb, path, payload)

        expect(response).to have_http_status(:unauthorized), "#{verb.upcase} #{path} answered #{response.status}"
        expect(response.parsed_body['error']).to be_present
      end

      # The refusal is a refusal, not a refusal that still wrote: nothing was created and nothing was removed.
      expect(account.custom_roles.reload).to contain_exactly(existing)
    end

    # §6: turning the capability off must not break an account that already uses it. Everything that reads a
    # membership keeps working, and turning the capability back on must have lost nothing.
    it 'leaves an existing attachment working everywhere else' do
      order_desk = create(:custom_role, account: account, name: 'Order desk', permissions: %w[commerce_order_manage])
      holder_membership.update!(custom_role: order_desk)

      get '/api/v1/profile', headers: role_holder.create_new_auth_token, as: :json
      payload = response.parsed_body['accounts'].find { |entry| entry['id'] == account.id }

      expect(response).to have_http_status(:success)
      expect(payload['permissions']).to contain_exactly('commerce_order_manage', 'custom_role')
      expect(payload['custom_role']).to include('name' => 'Order desk')

      as(admin, :get, 'agents')
      expect(response).to have_http_status(:success)
    end
  end
end
