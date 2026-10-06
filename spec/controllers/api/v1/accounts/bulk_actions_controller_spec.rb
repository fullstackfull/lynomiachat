require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::BulkActionsController', type: :request do
  include ActiveJob::TestHelper
  let(:account) { create(:account) }
  let(:agent_1) { create(:user, account: account, role: :agent) }
  let(:agent_2) { create(:user, account: account, role: :agent) }
  let(:team_1) { create(:team, account: account) }

  before do
    create(:conversation, account_id: account.id, status: :open, team_id: team_1.id)
    create(:conversation, account_id: account.id, status: :open, team_id: team_1.id)
    create(:conversation, account_id: account.id, status: :open)
    create(:conversation, account_id: account.id, status: :open)
    Conversation.all.find_each do |conversation|
      create(:inbox_member, inbox: conversation.inbox, user: agent_1)
      create(:inbox_member, inbox: conversation.inbox, user: agent_2)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/bulk_action' do
    context 'when it is an unauthenticated user' do
      let!(:agent) { create(:user) }

      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/bulk_actions",
             headers: agent.create_new_auth_token,
             params: { type: 'Conversation', fields: { status: 'open' }, ids: [1, 2, 3] }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let!(:agent) { create(:user, account: account, role: :agent) }

      before do
        Conversation.all.find_each { |conversation| create(:inbox_member, inbox: conversation.inbox, user: agent) }
      end

      it 'Ignores bulk_actions for wrong type' do
        post "/api/v1/accounts/#{account.id}/bulk_actions",
             headers: agent.create_new_auth_token,
             params: { type: 'Test', fields: { status: 'snoozed' }, ids: %w[1 2 3] }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'Bulk update conversation status' do
        expect(Conversation.first.status).to eq('open')
        expect(Conversation.last.status).to eq('open')
        expect(Conversation.first.assignee_id).to be_nil

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: { type: 'Conversation', fields: { status: 'snoozed' }, ids: Conversation.first(3).pluck(:display_id) }

          expect(response).to have_http_status(:success)
        end

        expect(Conversation.first.status).to eq('snoozed')
        expect(Conversation.last.status).to eq('open')
        expect(Conversation.first.assignee_id).to be_nil
      end

      it 'Bulk update conversation team id to none' do
        params = { type: 'Conversation', fields: { team_id: 0 }, ids: Conversation.first(1).pluck(:display_id) }
        expect(Conversation.first.team).not_to be_nil

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: params

          expect(response).to have_http_status(:success)
        end

        expect(Conversation.first.team).to be_nil

        last_activity_message = Conversation.first.messages.activity.last

        expect(last_activity_message.content).to eq("Unassigned from #{team_1.name} by #{agent.name}")
      end

      it 'Bulk update conversation team id to team' do
        params = { type: 'Conversation', fields: { team_id: team_1.id }, ids: Conversation.last(2).pluck(:display_id) }
        expect(Conversation.last.team_id).to be_nil

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: params

          expect(response).to have_http_status(:success)
        end

        expect(Conversation.last.team).to eq(team_1)

        last_activity_message = Conversation.last.messages.activity.last

        expect(last_activity_message.content).to eq("Assigned to #{team_1.name} by #{agent.name}")
      end

      it 'Bulk update conversation assignee id' do
        params = { type: 'Conversation', fields: { assignee_id: agent_1.id }, ids: Conversation.first(3).pluck(:display_id) }

        expect(Conversation.first.status).to eq('open')
        expect(Conversation.first.assignee_id).to be_nil
        expect(Conversation.second.assignee_id).to be_nil

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: params

          expect(response).to have_http_status(:success)
        end

        expect(Conversation.first.assignee_id).to eq(agent_1.id)
        expect(Conversation.second.assignee_id).to eq(agent_1.id)
        expect(Conversation.first.status).to eq('open')
      end

      it 'Bulk remove assignee id from conversations' do
        Conversation.first.update(assignee_id: agent_1.id)
        Conversation.second.update(assignee_id: agent_2.id)
        params = { type: 'Conversation', fields: { assignee_id: nil }, ids: Conversation.first(3).pluck(:display_id) }

        expect(Conversation.first.status).to eq('open')
        expect(Conversation.first.assignee_id).to eq(agent_1.id)
        expect(Conversation.second.assignee_id).to eq(agent_2.id)

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: params

          expect(response).to have_http_status(:success)
        end

        expect(Conversation.first.assignee_id).to be_nil
        expect(Conversation.second.assignee_id).to be_nil
        expect(Conversation.first.status).to eq('open')
      end

      it 'Do not bulk update status to nil' do
        Conversation.first.update(assignee_id: agent_1.id)
        Conversation.second.update(assignee_id: agent_2.id)
        params = { type: 'Conversation', fields: { status: nil }, ids: Conversation.first(3).pluck(:display_id) }

        expect(Conversation.first.status).to eq('open')

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: params

          expect(response).to have_http_status(:success)
        end

        expect(Conversation.first.status).to eq('open')
      end

      it 'Bulk update conversation status and assignee id' do
        params = { type: 'Conversation', fields: { assignee_id: agent_1.id, status: 'snoozed' }, ids: Conversation.first(3).pluck(:display_id) }

        expect(Conversation.first.status).to eq('open')
        expect(Conversation.second.assignee_id).to be_nil

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: params

          expect(response).to have_http_status(:success)
        end

        expect(Conversation.first.assignee_id).to eq(agent_1.id)
        expect(Conversation.second.assignee_id).to eq(agent_1.id)
        expect(Conversation.first.status).to eq('snoozed')
        expect(Conversation.second.status).to eq('snoozed')
      end

      it 'Bulk update conversation labels' do
        params = { type: 'Conversation', ids: Conversation.first(3).pluck(:display_id), labels: { add: %w[support priority_customer] } }

        expect(Conversation.first.labels).to eq([])
        expect(Conversation.second.labels).to eq([])

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: params

          expect(response).to have_http_status(:success)
        end

        expect(Conversation.first.label_list).to contain_exactly('support', 'priority_customer')
        expect(Conversation.second.label_list).to contain_exactly('support', 'priority_customer')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/bulk_actions' do
    context 'when it is an authenticated user' do
      let!(:agent) { create(:user, account: account, role: :agent) }

      before do
        Conversation.all.find_each { |conversation| create(:inbox_member, inbox: conversation.inbox, user: agent) }
      end

      it 'Bulk delete conversation labels' do
        Conversation.first.add_labels(%w[support priority_customer])
        Conversation.second.add_labels(%w[support priority_customer])
        Conversation.third.add_labels(%w[support priority_customer])

        params = { type: 'Conversation', ids: Conversation.first(3).pluck(:display_id), labels: { remove: %w[support] } }

        expect(Conversation.first.label_list).to contain_exactly('support', 'priority_customer')
        expect(Conversation.second.label_list).to contain_exactly('support', 'priority_customer')

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: params

          expect(response).to have_http_status(:success)
        end

        expect(Conversation.first.label_list).to contain_exactly('priority_customer')
        expect(Conversation.second.label_list).to contain_exactly('priority_customer')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/bulk_actions (contacts)' do
    context 'when it is an authenticated user' do
      let!(:agent) { create(:user, account: account, role: :agent) }

      it 'enqueues Contacts::BulkActionJob with permitted params' do
        contact_one = create(:contact, account: account)
        contact_two = create(:contact, account: account)
        %w[vip support].each { |title| create(:label, account: account, title: title) }

        expect do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: {
                 type: 'Contact',
                 ids: [contact_one.id, contact_two.id],
                 labels: { add: %w[vip support] },
                 extra: 'ignored'
               }
        end.to have_enqueued_job(Contacts::BulkActionJob).with(
          account.id,
          agent.id,
          hash_including(
            'ids' => [contact_one.id.to_s, contact_two.id.to_s],
            'labels' => hash_including('add' => %w[vip support])
          )
        )

        expect(response).to have_http_status(:success)
      end

      it 'applies an addition and a removal from one payload' do
        contact = create(:contact, account: account)
        create(:label, account: account, title: 'vip')
        contact.add_labels('prospect')

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: { type: 'Contact', ids: [contact.id], labels: { add: ['vip'], remove: ['prospect'] } }
        end

        expect(response).to have_http_status(:success)
        expect(contact.reload.label_list).to contain_exactly('vip')
      end

      it 'refuses a label the account does not have, enqueueing nothing' do
        contact = create(:contact, account: account)

        expect do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: { type: 'Contact', ids: [contact.id], labels: { add: ['ghost'] } }
        end.not_to have_enqueued_job(Contacts::BulkActionJob)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error_types']['labels']).to eq(['not_in_account'])
      end

      it 'refuses another account\'s label' do
        contact = create(:contact, account: account)
        create(:label, account: create(:account), title: 'elsewhere')

        post "/api/v1/accounts/#{account.id}/bulk_actions",
             headers: agent.create_new_auth_token,
             params: { type: 'Contact', ids: [contact.id], labels: { add: ['elsewhere'] } }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'still removes a label the catalogue no longer holds, so an old tag can be cleaned up' do
        contact = create(:contact, account: account)
        contact.add_labels('off-catalogue')

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: { type: 'Contact', ids: [contact.id], labels: { remove: ['off-catalogue'] } }
        end

        expect(response).to have_http_status(:success)
        expect(contact.reload.label_list).to be_empty
      end

      it 'never reaches another account\'s contact' do
        other_contact = create(:contact, account: create(:account))
        create(:label, account: account, title: 'vip')

        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: { type: 'Contact', ids: [other_contact.id], labels: { add: ['vip'] } }
        end

        expect(response).to have_http_status(:success)
        expect(other_contact.reload.label_list).to be_empty
      end

      it 'permits contact label removal params' do
        contact_one = create(:contact, account: account)
        contact_two = create(:contact, account: account)

        expect do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: agent.create_new_auth_token,
               params: {
                 type: 'Contact',
                 ids: [contact_one.id, contact_two.id],
                 labels: { remove: %w[vip support] },
                 extra: 'ignored'
               }
        end.to have_enqueued_job(Contacts::BulkActionJob).with(
          account.id,
          agent.id,
          hash_including(
            'ids' => [contact_one.id.to_s, contact_two.id.to_s],
            'labels' => hash_including('remove' => %w[vip support])
          )
        )

        expect(response).to have_http_status(:success)
      end

      it 'returns unauthorized for delete action when user is not admin' do
        contact = create(:contact, account: account)

        post "/api/v1/accounts/#{account.id}/bulk_actions",
             headers: agent.create_new_auth_token,
             params: {
               type: 'Contact',
               ids: [contact.id],
               action_name: 'delete'
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # D4 (docs/contacts/10-phase-d.md). A bulk action over every contact a view matches, not only the page the
  # browser is holding.
  describe 'POST /api/v1/accounts/{account.id}/bulk_actions over a whole view' do
    let(:account) { create(:account) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let!(:vip) { create(:label, account: account, title: 'vip') }

    # As JSON, like the dashboard: a form-encoded body cannot carry an empty `all_matching`, and the whole point
    # of this contract is that an empty description is a description.
    def bulk(params)
      post "/api/v1/accounts/#{account.id}/bulk_actions", headers: agent.create_new_auth_token, params: params, as: :json
    end

    def contact_jobs
      enqueued_jobs.select { |job| job[:job] == Contacts::BulkActionJob }
    end

    def enqueued_ids
      contact_jobs.flat_map { |job| Array(job[:args].last['ids']) }
    end

    before { vip }

    it 'resolves a label view to every contact carrying that label' do
      tagged = [create(:contact, account: account, phone_number: '+966551110001'),
                create(:contact, account: account, phone_number: '+966551110002')]
      tagged.each { |contact| contact.add_labels(['vip']) }
      create(:contact, account: account, phone_number: '+966551119999')

      bulk({ type: 'Contact', all_matching: { label: 'vip' }, labels: { add: ['vip'] } })

      expect(response).to have_http_status(:success)
      expect(enqueued_ids).to match_array(tagged.map(&:id))
    end

    it 'resolves a search view with the search endpoint\'s own predicate' do
      match = create(:contact, account: account, name: 'Ahmed Zaki')
      create(:contact, account: account, name: 'Someone Else')

      bulk({ type: 'Contact', all_matching: { q: 'zaki' }, labels: { add: ['vip'] } })

      expect(enqueued_ids).to eq([match.id])
    end

    it 'resolves a filter view through Contacts::FilterService' do
      match = create(:contact, account: account, email: 'wholesale@example.com')
      create(:contact, account: account, email: 'retail@example.com')

      bulk({ type: 'Contact',
             all_matching: { payload: [{ attribute_key: 'email', filter_operator: 'contains', values: 'wholesale',
                                         query_operator: nil, attribute_model: 'standard', custom_attribute_type: '' }] },
             labels: { add: ['vip'] } })

      expect(response).to have_http_status(:success)
      expect(enqueued_ids).to eq([match.id])
    end

    it 'never reaches another account, whatever the view says' do
      mine = create(:contact, account: account, name: 'Ahmed Zaki')
      create(:contact, account: create(:account), name: 'Ahmed Zaki')

      bulk({ type: 'Contact', all_matching: { q: 'zaki' }, labels: { add: ['vip'] } })

      expect(enqueued_ids).to eq([mine.id])
    end

    it 'takes an empty description as the unfiltered list, because somebody asked for it in so many words' do
      listed = create(:contact, account: account, phone_number: '+966551110001')
      # The unfiltered list is `resolved_contacts`, exactly as `/contacts` is, so a row with no identity is no
      # more reachable here than it is on the page.
      unlisted = create(:contact, account: account)

      bulk({ type: 'Contact', all_matching: {}, labels: { add: ['vip'] } })

      expect(response).to have_http_status(:success)
      expect(enqueued_ids).to include(listed.id)
      expect(enqueued_ids).not_to include(unlisted.id)
    end

    it 'never reads a missing description as every contact in the account' do
      create(:contact, account: account)

      bulk({ type: 'Contact', labels: { add: ['vip'] } })

      expect(response).to have_http_status(:success)
      expect(enqueued_ids).to be_empty
    end

    it 'refuses a view with more contacts than one action may touch, rather than doing some of them' do
      create_list(:contact, 3, account: account)
      stub_const('Api::V1::Accounts::BulkActionsController::CONTACT_VIEW_LIMIT', 2)

      bulk({ type: 'Contact', all_matching: {}, labels: { add: ['vip'] } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_types']['base']).to eq(['too_many_contacts'])
      expect(contact_jobs).to be_empty
    end

    it 'still refuses a label the account does not have' do
      create(:contact, account: account)

      bulk({ type: 'Contact', all_matching: {}, labels: { add: ['ghost'] } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_types']['labels']).to eq(['not_in_account'])
    end

    it 'still refuses a delete from a user who may not delete' do
      create(:contact, account: account)

      bulk({ type: 'Contact', all_matching: {}, action_name: 'delete' })

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
