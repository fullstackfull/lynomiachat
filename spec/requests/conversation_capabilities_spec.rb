require 'rails_helper'

# DECISION 1, asserted where an attacker meets it: over HTTP, on the real endpoints.
#
# spec/services/conversations/capability_scope_spec.rb covers the rule itself. This file exists because a rule
# that holds in a unit and not on the endpoint is not enforcement -- and because the decision named the four
# things that have to agree: the list, the count, the record and search. Each gets its own example here, and
# each is asserted for the two narrowing modes rather than only the easy one.
RSpec.describe 'Conversation capabilities, enforced server-side', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:membership) { account.account_users.find_by(user: agent) }

  # One contact, named so that a single `q` matches every conversation through the contact-name leg of
  # SearchService#filter_conversations and every message through the content leg of filter_messages.
  let(:contact) { create(:contact, account: account, name: 'Zaphod Beeblebrox') }

  let!(:mine) { conversation_with_message(assignee: agent) }
  let!(:unassigned) { conversation_with_message(assignee: nil) }
  let!(:theirs) { conversation_with_message(assignee: other_agent) }

  before do
    account.enable_features!('custom_roles')
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_member, inbox: inbox, user: other_agent)
  end

  def conversation_with_message(assignee:)
    create(:conversation, account: account, inbox: inbox, contact: contact, assignee: assignee).tap do |conversation|
      create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Zaphod asked about the order')
    end
  end

  def attach(*permissions)
    membership.update!(custom_role: create(:custom_role, account: account, permissions: permissions), role: :agent)
  end

  def listed_display_ids
    get "/api/v1/accounts/#{account.id}/conversations", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['data']['payload'].pluck('id')
  end

  describe 'the conversation list' do
    it 'returns everything for conversation_manage' do
      attach('conversation_manage')

      expect(listed_display_ids).to contain_exactly(mine.display_id, unassigned.display_id, theirs.display_id)
    end

    it 'returns the unassigned ones and their own for conversation_unassigned_manage' do
      attach('conversation_unassigned_manage')

      expect(listed_display_ids).to contain_exactly(mine.display_id, unassigned.display_id)
    end

    it 'returns only their own for conversation_participating_manage' do
      attach('conversation_participating_manage')

      expect(listed_display_ids).to contain_exactly(mine.display_id)
    end

    it 'returns nothing for a set that names none of the three' do
      attach('contact_manage')

      expect(listed_display_ids).to be_empty
    end
  end

  describe 'the meta counts, which have to agree with the list' do
    # A count that disagrees with the list is the failure mode this example exists for: a holder who is told
    # there are five open conversations and shown one has been refused access by a number rather than by a
    # rule.
    it 'counts exactly what the list returns, for every mode' do
      [['conversation_manage', 3], ['conversation_unassigned_manage', 2], ['conversation_participating_manage', 1],
       ['contact_manage', 0]].each do |capability, expected|
        attach(capability)

        get "/api/v1/accounts/#{account.id}/conversations/meta", headers: agent.create_new_auth_token, as: :json

        expect(response.parsed_body['meta']['all_count']).to eq(expected), "#{capability} counted wrongly"
        expect(listed_display_ids.length).to eq(expected)
      end
    end
  end

  describe 'the filter endpoint' do
    it 'narrows the same way the list does' do
      attach('conversation_participating_manage')

      post "/api/v1/accounts/#{account.id}/conversations/filter",
           headers: agent.create_new_auth_token,
           params: { payload: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'] }] },
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(mine.display_id)
    end
  end

  describe 'direct access to one conversation, which is the endpoint a narrowed list invites' do
    # The point of the record half. A holder who cannot see a conversation in the list used to be able to open
    # it, its messages and its attachments by typing the display id.
    it 'refuses a conversation the capability excludes' do
      attach('conversation_participating_manage')

      get "/api/v1/accounts/#{account.id}/conversations/#{theirs.display_id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an unassigned conversation to a participating-only holder' do
      attach('conversation_participating_manage')

      get "/api/v1/accounts/#{account.id}/conversations/#{unassigned.display_id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows the unassigned one to a holder of conversation_unassigned_manage' do
      attach('conversation_unassigned_manage')

      get "/api/v1/accounts/#{account.id}/conversations/#{unassigned.display_id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'still allows their own conversation' do
      attach('conversation_participating_manage')

      get "/api/v1/accounts/#{account.id}/conversations/#{mine.display_id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'refuses the messages of an excluded conversation, which hang off the same authorization' do
      attach('conversation_participating_manage')

      get "/api/v1/accounts/#{account.id}/conversations/#{theirs.display_id}/messages",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'global search, which never went through the list filter at all' do
    it 'narrows the conversation results' do
      attach('conversation_participating_manage')

      get "/api/v1/accounts/#{account.id}/search/conversations",
          headers: agent.create_new_auth_token, params: { q: 'Zaphod' }, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['conversations'].pluck('id')).to contain_exactly(mine.display_id)
    end

    # The leg that leaks content rather than metadata. This agent belongs to every inbox in the account, so
    # `should_skip_inbox_filtering?` drops the message inbox filter entirely -- the narrowing below is what is
    # left.
    it 'narrows the message results, bodies included' do
      attach('conversation_participating_manage')

      get "/api/v1/accounts/#{account.id}/search/messages",
          headers: agent.create_new_auth_token, params: { q: 'Zaphod' }, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']['messages'].pluck('conversation_id')).to contain_exactly(mine.display_id)
    end

    it 'returns no message at all for a set that names none of the three' do
      attach('contact_manage')

      get "/api/v1/accounts/#{account.id}/search/messages",
          headers: agent.create_new_auth_token, params: { q: 'Zaphod' }, as: :json

      expect(response.parsed_body['payload']['messages']).to be_empty
    end

    it 'narrows the combined search endpoint too' do
      attach('conversation_unassigned_manage')

      get "/api/v1/accounts/#{account.id}/search",
          headers: agent.create_new_auth_token, params: { q: 'Zaphod' }, as: :json

      expect(response.parsed_body['payload']['conversations'].pluck('id'))
        .to contain_exactly(mine.display_id, unassigned.display_id)
    end
  end

  describe 'existing roles, which must not lose access on upgrade' do
    it 'leaves a grandfathered set reading everything it could read before' do
      attach('contact_manage')
      membership.custom_role.update_column(:conversation_scope_enforced, false) # rubocop:disable Rails/SkipsModelValidations

      expect(listed_display_ids).to contain_exactly(mine.display_id, unassigned.display_id, theirs.display_id)

      get "/api/v1/accounts/#{account.id}/conversations/#{theirs.display_id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  describe 'the entitlement upper bound (DECISION 2) over HTTP' do
    it 'stops narrowing by a capability the account is no longer entitled to hold' do
      attach('conversation_participating_manage')
      expect(listed_display_ids).to contain_exactly(mine.display_id)

      account.disable_features!('custom_roles')

      expect(listed_display_ids).to contain_exactly(mine.display_id, unassigned.display_id, theirs.display_id)
    end

    it 'does not hand the holder anything an administrator can reach' do
      attach('conversation_participating_manage')
      account.disable_features!('custom_roles')

      delete "/api/v1/accounts/#{account.id}/conversations/#{mine.display_id}",
             headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'tenant isolation' do
    let(:other_account) { create(:account) }
    let!(:foreign) do
      create(:conversation, account: other_account, inbox: create(:inbox, account: other_account),
                            contact: create(:contact, account: other_account), assignee: nil)
    end

    it 'refuses a foreign conversation to a holder whose capability would otherwise reach it' do
      attach('conversation_unassigned_manage')

      get "/api/v1/accounts/#{other_account.id}/conversations/#{foreign.display_id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).not_to have_http_status(:success)
    end

    # The interesting half: the same person, a member of both accounts, with a narrowing set in one of them.
    # A capability belongs to a membership, not to a user, so it must not follow them across the boundary.
    it 'keeps a narrowing set inside the account that granted it' do
      attach('conversation_participating_manage')
      create(:account_user, account: other_account, user: agent, role: :agent)
      other_inbox = foreign.inbox
      create(:inbox_member, inbox: other_inbox, user: agent)

      get "/api/v1/accounts/#{other_account.id}/conversations", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['data']['payload'].pluck('id')).to contain_exactly(foreign.display_id)
      expect(listed_display_ids).to contain_exactly(mine.display_id)
    end
  end
end
