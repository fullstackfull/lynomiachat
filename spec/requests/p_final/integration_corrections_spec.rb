require 'rails_helper'

# Four corrections made to the clean-room packages after they were integrated, each found by the post-merge
# audits rather than by the packages' own acceptance plans.
#
# They live here instead of in the package specs so that those files stay exactly as they were written and
# imported — docs/p-final/04-code-provenance.md §8 rests on that — and so a reviewer can read what changed after
# the merge in one place.
RSpec.describe 'Clean-room integration corrections', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'a membership holding a permission set is an agent' do
    let(:other_admin) { create(:user, account: account, role: :administrator) }
    let(:other_membership) { account.account_users.find_by(user: other_admin) }
    let!(:order_desk) { create(:custom_role, account: account, name: 'Order desk', permissions: %w[commerce_order_manage]) }

    before { account.enable_features!('custom_roles') }

    def update_agent(payload, as: admin)
      patch "/api/v1/accounts/#{account.id}/agents/#{other_admin.id}",
            params: { agent: payload }, headers: as.create_new_auth_token, as: :json
    end

    # The edit page offers the built-in roles and the account's sets in one selector and sends only
    # `custom_role_id` when a set is chosen (settings/agents/EditAgent.vue:131-136). Before this, the membership
    # kept `role = administrator`: the set was attached and displayed, every administrator endpoint stayed open —
    # including the roles endpoint that defines the set meant to narrow them — and the one server reader of a
    # set's capabilities ignored the set entirely, because it counts only a membership that is also an agent
    # (app/services/conversations/unread_counts/counter.rb:170-172).
    it 'moves an administrator to agent when a set is attached without naming a role' do
      update_agent({ custom_role_id: order_desk.id })

      expect(response).to have_http_status(:success)
      expect(other_membership.reload).to have_attributes(role: 'agent', custom_role_id: order_desk.id)
      expect(other_membership.permissions).to contain_exactly('commerce_order_manage', 'custom_role')
    end

    it 'refuses a request that asks for administrator and a set at once, and changes nothing' do
      update_agent({ role: 'administrator', custom_role_id: order_desk.id })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(other_membership.reload).to have_attributes(role: 'administrator', custom_role_id: nil)
    end

    # Detaching is the other direction and must stay untouched: the page sends the built-in role with the null,
    # and that role is what the membership gets.
    it 'honours a detachment that names administrator' do
      other_membership.update!(custom_role: order_desk, role: :agent)

      update_agent({ role: 'administrator', custom_role_id: nil })

      expect(response).to have_http_status(:success)
      expect(other_membership.reload).to have_attributes(role: 'administrator', custom_role_id: nil)
      expect(other_membership.permissions).to eq(%w[administrator])
    end
  end

  describe 'editing a set invalidates its holders’ cached visibility' do
    let(:holder) { create(:user, account: account, role: :agent) }
    let!(:role) { create(:custom_role, account: account, name: 'Support lead', permissions: %w[conversation_manage]) }
    # `user_visibility_changed!` is allowed because creating a membership calls it (app/models/account_user.rb:42);
    # the assertions below are about the plural message, which only an edit to the set itself sends.
    let(:invalidator) do
      instance_double(Conversations::UnreadCounts::FilteredCountInvalidator,
                      users_visibility_changed!: true, user_visibility_changed!: true)
    end

    before do
      account.enable_features!('custom_roles')
      admin
      account.account_users.find_by(user: holder).update!(custom_role: role)
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).and_return(invalidator)
    end

    def update_role(payload)
      patch "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}",
            params: { custom_role: payload }, headers: admin.create_new_auth_token, as: :json
    end

    # Three of the vocabulary's capabilities decide how much of the inbox a member's filtered unread counts
    # cover, and those counts are cached per member in Redis. Chatwoot bumps the version when the attachment
    # moves; narrowing the set is the same change for every holder, and no membership row changes, so without
    # this they keep counting under the capabilities the set used to grant.
    it 'tells the unread-count cache when the capability list changes' do
      update_role({ permissions: %w[conversation_participating_manage] })

      expect(response).to have_http_status(:success)
      expect(invalidator).to have_received(:users_visibility_changed!).with(user_ids: [holder.id])
    end

    it 'says nothing when only the name changes' do
      update_role({ name: 'Support lead (EMEA)' })

      expect(response).to have_http_status(:success)
      expect(invalidator).not_to have_received(:users_visibility_changed!)
    end
  end

  # Specification A §2: "Unparseable or out-of-range values must not raise. They are either ignored or answered
  # with an empty page; they must never produce a 500." A query string can carry any shape, and an array-valued
  # parameter reached `to_i`, which an Array does not answer.
  describe 'a query parameter of an unexpected shape' do
    before do
      account.enable_features!('audit_logs')
      admin
    end

    it 'does not raise on an array-valued page in the audit trail' do
      get "/api/v1/accounts/#{account.id}/audit_logs",
          params: { page: %w[2 3] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['current_page']).to eq(1)
    end

    it 'does not raise on an array-valued actor filter in the audit trail' do
      get "/api/v1/accounts/#{account.id}/audit_logs",
          params: { user_id: [admin.id.to_s] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'does not raise on an array-valued page in campaign recipient analytics' do
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                          validate_provider_config: false)
      campaign = create(:campaign, account: account, inbox: channel.inbox)

      get "/api/v1/accounts/#{account.id}/campaigns/#{campaign.id}/analytics/contacts",
          params: { page: %w[2 3] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end
end
