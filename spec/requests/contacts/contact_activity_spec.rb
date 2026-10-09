require 'rails_helper'

RSpec.describe 'Contact activity timeline', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  def get_activity(params = {}, as: administrator, for_account: account, for_contact: nil)
    get "/api/v1/accounts/#{for_account.id}/contacts/#{(for_contact || contact).id}/activity",
        params: params, headers: as.create_new_auth_token
  end

  describe 'authorization' do
    it 'refuses an unauthenticated caller' do
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/activity"
      expect(response).to have_http_status(:unauthorized)
    end

    # Unlike the analytics screens, this follows the contact's own policy: an agent who may open a contact may
    # see what happened with it.
    it 'allows an agent, because the contact policy allows them to see the contact' do
      create(:inbox_member, user: agent, inbox: inbox)
      get_activity(as: agent)
      expect(response).to have_http_status(:success)
    end

    it "refuses an administrator of another account on this account's contact" do
      get_activity(as: other_administrator)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'answers 404 for a contact that belongs to another account' do
      foreign = create(:contact, account: other_account)
      get_activity({}, for_contact: foreign)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'payload' do
    before do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                       content: 'I need help', created_at: 1.hour.ago)
    end

    it 'returns entries and a bounded meta block' do
      get_activity

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.keys).to match_array(%w[payload meta])
      expect(response.parsed_body['meta']).to include('limit' => Contacts::ActivityTimelineQuery::DEFAULT_LIMIT,
                                                      'partial' => false)
    end

    it 'carries the normalised entry shape' do
      get_activity

      entry = response.parsed_body['payload'].find { |row| row['kind'] == 'message_incoming' }

      expect(entry.keys).to include('id', 'source', 'category', 'kind', 'occurred_at', 'conversation_id')
      expect(entry['summary']).to eq('I need help')
    end

    it 'narrows to the requested categories' do
      get_activity({ categories: ['messages'] })

      expect(response.parsed_body['meta']['categories']).to eq(['messages'])
      expect(response.parsed_body['payload'].pluck('category').uniq).to eq(['messages'])
    end

    it 'hides activity from a conversation the agent cannot open' do
      create(:inbox_member, user: agent, inbox: inbox)
      hidden = create(:conversation, account: account, inbox: other_inbox, contact: contact)
      create(:message, account: account, inbox: other_inbox, conversation: hidden, message_type: :incoming,
                       content: 'other inbox', created_at: 1.hour.ago)

      get_activity({}, as: agent)

      expect(response.parsed_body['payload'].pluck('summary')).not_to include('other inbox')
    end
  end

  describe 'pagination' do
    before do
      5.times do |index|
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                         content: "m#{index}", created_at: (index + 1).hours.ago)
      end
    end

    it 'follows its own cursor without repeating a row' do
      get_activity({ limit: 2 })
      first_ids = response.parsed_body['payload'].pluck('id')
      cursor = response.parsed_body['meta']['next_cursor']

      expect(cursor).to be_present

      get_activity({ limit: 2, cursor: cursor })
      second_ids = response.parsed_body['payload'].pluck('id')

      expect(first_ids & second_ids).to be_empty
    end
  end

  describe 'rejected requests' do
    it 'refuses a limit above the maximum with 422' do
      get_activity({ limit: 500 })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('100')
    end

    it 'refuses a malformed cursor with 422' do
      get_activity({ cursor: 'nope' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('cursor')
    end

    it 'refuses an unknown category with 422 and the allowed list' do
      get_activity({ categories: ['invoices'] })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('messages, conversations, campaigns, automations, commerce')
    end
  end
end
