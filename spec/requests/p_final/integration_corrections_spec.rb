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
  # Specification A §2 lists `q` nowhere, and neither did the integration contract, so the rewrite had nothing
  # to implement it from — while the settings page has shipped a search box that sends it since the audit trail
  # existed, and counts it among its active filters. An ignored `q` therefore presented an unfiltered trail as a
  # filtered one.
  describe 'the audit trail search box' do
    let(:other_admin) { create(:user, account: account, role: :administrator, name: 'Noura Al-Rashed') }

    before do
      account.enable_features!('audit_logs')
      admin.update!(name: 'Faisal Al-Sabah')
      other_admin
      Custom::AuditLog.delete_all
      Custom::AuditLog.create!(associated_type: 'Account', associated_id: account.id, action: 'update',
                               auditable_type: 'Account', auditable_id: account.id,
                               user_id: admin.id, user_type: 'User', username: admin.name)
      Custom::AuditLog.create!(associated_type: 'Account', associated_id: account.id, action: 'update',
                               auditable_type: 'Inbox', auditable_id: 1,
                               user_id: other_admin.id, user_type: 'User', username: other_admin.name)
    end

    def search(term)
      get "/api/v1/accounts/#{account.id}/audit_logs",
          params: { q: term }, headers: admin.create_new_auth_token, as: :json
      response.parsed_body
    end

    it 'restricts the trail to entries whose recorded actor matches, case-insensitively and on a fragment' do
      body = search('al-rashed')

      expect(body['total_entries']).to eq(1)
      expect(body['audit_logs'].map { |entry| entry['username'] }).to eq(['Noura Al-Rashed'])
    end

    it 'returns an empty page rather than everything when nothing matches' do
      expect(search('nobody-by-that-name')['total_entries']).to eq(0)
    end

    # The actor name is captured on the row at write time precisely so an entry stays attributable after the
    # person's record is gone. Searching the live `users` table would lose exactly those entries.
    it 'still finds an entry whose actor no longer exists' do
      other_admin.account_users.destroy_all
      other_admin.destroy!

      expect(search('al-rashed')['total_entries']).to eq(1)
    end

    it 'treats a blank search as no search at all' do
      expect(search('   ')['total_entries']).to eq(2)
    end

    # `%` and `_` are LIKE wildcards; a term containing them must match them literally rather than everything.
    it 'does not let a wildcard in the term widen the search' do
      expect(search('%')['total_entries']).to eq(0)
    end
  end

  # `Time.zone.at` answers year 31690708 for 10**15 without raising, so the value became a real Time, reached
  # PostgreSQL — whose `timestamp` maximum is 294276 AD — as a literal it rejects, and the request 500d.
  describe 'an out-of-range date bound on the audit trail' do
    before do
      account.enable_features!('audit_logs')
      admin
    end

    it 'ignores the window instead of reaching the database' do
      get "/api/v1/accounts/#{account.id}/audit_logs",
          params: { since: 0, until: 10**15 }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['total_entries']).to eq(Custom::AuditLog.for_account(account).count)
    end
  end

  # Specification D §2: `audience` is "the denominator of every rate the UI computes" and `status_counts` must
  # carry `queued`, which the page uses to word its "still processing" banner. Rows written only as each
  # contact's turn came made the denominator grow with the run and `queued` unreachable.
  describe 'the campaign audience snapshot' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false)
    end
    let(:label) { create(:label, account: account, title: 'autumn') }
    let(:campaign) do
      create(:campaign, account: account, inbox: channel.inbox, audience: [{ type: 'Label', id: label.id }])
    end
    let!(:contacts) do
      Array.new(3) do |index|
        create(:contact, account: account, phone_number: "+9655000000#{index}").tap do |contact|
          contact.update_labels([label.title])
        end
      end
    end

    it 'records every addressed contact at queued before the first send' do
      Campaigns::RecipientSnapshot.new(campaign).seed(campaign.audience_contacts)

      recipients = CampaignRecipient.where(campaign: campaign)
      expect(recipients.count).to eq(3)
      expect(recipients.pluck(:status).uniq).to eq(['queued'])
      expect(recipients.pluck(:contact_id)).to match_array(contacts.map(&:id))
    end

    # A campaign can be seeded again — a retry, or a second run — and an outcome already recorded must not be
    # reset to queued by it.
    it 'leaves an outcome already recorded alone when seeded again' do
      snapshot = Campaigns::RecipientSnapshot.new(campaign)
      snapshot.seed(campaign.audience_contacts)
      snapshot.sent(contacts.first, source_id: 'wamid.first')

      snapshot.seed(campaign.audience_contacts)

      expect(CampaignRecipient.find_by(campaign: campaign, contact: contacts.first)).to have_attributes(
        status: 'sent', source_id: 'wamid.first'
      )
      expect(CampaignRecipient.where(campaign: campaign).count).to eq(3)
    end

    it 'reports the whole audience as the denominator with the remainder still queued' do
      snapshot = Campaigns::RecipientSnapshot.new(campaign)
      snapshot.seed(campaign.audience_contacts)
      snapshot.sent(contacts.first, source_id: 'wamid.first')

      metrics = Campaigns::RecipientMetrics.new(campaign).as_json

      expect(metrics['audience']).to eq(3)
      expect(metrics['status_counts']).to include('queued' => 2, 'sent' => 1)
    end
  end

  # Custom::Audit::Capture is what keeps a rejected audit row from aborting the product action that caused it,
  # and what honours AuditTrail::Capture.suppressed?. The audience concern was the one capture point that
  # declared `audited` without prepending it.
  describe 'audience audit capture' do
    it 'does not fail the product action when the audit row cannot be written' do
      allow_any_instance_of(Custom::AuditLog).to receive(:create_or_update).and_raise(ActiveRecord::StatementInvalid, 'nope')

      audience = nil
      expect do
        audience = create(:custom_filter, account: account, user: admin, filter_type: :contact)
      end.not_to raise_error

      expect(audience.reload).to be_persisted
    end

    it 'honours a suppressed capture' do
      expect do
        AuditTrail::Capture.suppressed { create(:custom_filter, account: account, user: admin, filter_type: :contact) }
      end.not_to change(Custom::AuditLog, :count)
    end
  end
end
