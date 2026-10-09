require 'rails_helper'

RSpec.describe 'Support tickets API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    account.enable_features!('lynomia_support_tickets')
    other_account.enable_features!('lynomia_support_tickets')
  end

  def index(params = {}, as: administrator, for_account: account)
    get "/api/v1/accounts/#{for_account.id}/support/tickets", params: params, headers: as.create_new_auth_token
  end

  def create_ticket(payload, as: administrator, for_account: account)
    post "/api/v1/accounts/#{for_account.id}/support/tickets",
         params: { ticket: payload }, headers: as.create_new_auth_token
  end

  def update_ticket(ticket, payload, as: administrator, for_account: account)
    patch "/api/v1/accounts/#{for_account.id}/support/tickets/#{ticket.id}",
          params: { ticket: payload }, headers: as.create_new_auth_token
  end

  describe 'the feature gate' do
    it 'answers 404 when the account has no support module' do
      account.disable_features!('lynomia_support_tickets')
      index
      expect(response).to have_http_status(:not_found)
    end

    it 'answers 401 for an unauthenticated caller' do
      get "/api/v1/accounts/#{account.id}/support/tickets"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows an agent, because working cases is the point of the feature' do
      index(as: agent)
      expect(response).to have_http_status(:success)
    end

    it "refuses an administrator of another account on this account's cases" do
      index(as: other_administrator)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'create' do
    it 'opens a case, numbers it and records the opening' do
      create_ticket({ title: 'Order never arrived', category: 'commerce', priority: 'high',
                      conversation_id: conversation.id, contact_id: contact.id, inbox_id: inbox.id })

      expect(response).to have_http_status(:created)
      body = response.parsed_body['payload']
      expect(body['reference']).to eq('TCK-000001')
      expect(body['status']).to eq('open')
      expect(body['conversation_display_id']).to eq(conversation.display_id)
      expect(Support::Ticket.last.events.pluck(:event_type)).to eq(['created'])
    end

    it 'opens an internal case with no customer, no channel and no conversation' do
      create_ticket({ title: 'IMAP inbox failing', category: 'operational' })

      expect(response).to have_http_status(:created)
      body = response.parsed_body['payload']
      expect([body['conversation_id'], body['contact_id'], body['inbox_id']]).to all(be_nil)
    end

    it 'records who opened it from the session, never from the request' do
      create_ticket({ title: 'Spoof attempt', created_by_id: agent.id })

      expect(Support::Ticket.last.created_by_id).to eq(administrator.id)
    end

    # account_id, reference_number and every SLA timestamp are owned by the services that set them.
    it 'ignores an attempt to set the account, the reference or an SLA timestamp' do
      create_ticket({ title: 'Mass assignment', account_id: other_account.id, reference_number: 9999,
                      resolution_due_at: 1.day.from_now, resolution_breached_at: 1.day.ago })

      ticket = Support::Ticket.last
      expect(ticket.account_id).to eq(account.id)
      expect(ticket.reference_number).to eq(1)
      expect(ticket.resolution_due_at).to be_nil
      expect(ticket.resolution_breached_at).to be_nil
    end

    it 'cannot be created already resolved' do
      create_ticket({ title: 'Skip the lifecycle', status: 'resolved' })

      expect(Support::Ticket.last.status).to eq('open')
    end

    it 'answers 404 for a link that belongs to another account' do
      create_ticket({ title: 'Cross tenant', contact_id: create(:contact, account: other_account).id })
      expect(response).to have_http_status(:not_found)

      create_ticket({ title: 'Cross tenant', conversation_id: create(:conversation, account: other_account).id })
      expect(response).to have_http_status(:not_found)

      create_ticket({ title: 'Cross tenant', assignee_id: create(:user, account: other_account, role: :agent).id })
      expect(response).to have_http_status(:not_found)
    end

    it 'answers 422 for a category outside the allow-list' do
      create_ticket({ title: 'Bad category', category: 'invented' })
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'update' do
    let(:ticket) { create(:support_ticket, account: account) }

    it 'moves the case and records the change' do
      update_ticket(ticket, { status: 'in_progress', priority: 'urgent' })

      expect(response).to have_http_status(:success)
      expect(ticket.reload.status).to eq('in_progress')
      expect(ticket.events.pluck(:event_type)).to contain_exactly('status_changed', 'priority_changed')
    end

    it 'answers 422 with the attempted edge for a transition the table refuses' do
      update_ticket(ticket, { status: 'closed' })
      update_ticket(ticket.reload, { status: 'resolved' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include("from 'closed' to 'resolved'")
    end

    it 'answers 404 for a case in another account' do
      theirs = create(:support_ticket, account: other_account)
      patch "/api/v1/accounts/#{account.id}/support/tickets/#{theirs.id}",
            params: { ticket: { priority: 'high' } }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 rather than 403 for a case the caller may not see' do
      someone_elses = create(:support_ticket, account: account, assignee: administrator)
      update_ticket(someone_elses, { priority: 'high' }, as: agent)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'show' do
    it 'accepts an id or a pasted reference' do
      ticket = create(:support_ticket, account: account)

      get "/api/v1/accounts/#{account.id}/support/tickets/#{ticket.id}", headers: administrator.create_new_auth_token
      expect(response.parsed_body['payload']['id']).to eq(ticket.id)

      get "/api/v1/accounts/#{account.id}/support/tickets/#{ticket.reference}",
          headers: administrator.create_new_auth_token
      expect(response.parsed_body['payload']['id']).to eq(ticket.id)
    end
  end

  describe 'index' do
    it 'returns the tab counts alongside the page, both narrowed to what the caller may see' do
      create(:support_ticket, account: account, assignee: agent, status: :open)
      create(:support_ticket, account: account, assignee: administrator, status: :resolved)

      index(as: agent)
      meta = response.parsed_body['meta']

      expect(meta['counts']).to include('all' => 1, 'mine' => 1, 'resolved' => 0)
      expect(response.parsed_body['payload'].length).to eq(1)
    end

    it 'answers 422 naming the allowed values for a bad filter' do
      index({ status: 'escalated' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('is not a ticket status')
    end

    it 'pages with an explicit bound' do
      3.times { create(:support_ticket, account: account) }

      index({ per_page: 2 })
      expect(response.parsed_body['meta']).to include('total_entries' => 3, 'per_page' => 2)
    end
  end

  describe 'what the payload does not contain' do
    it 'carries ids, enum values and timestamps only' do
      ticket = create(:support_ticket, account: account, conversation: conversation, contact: contact)
      get "/api/v1/accounts/#{account.id}/support/tickets/#{ticket.id}", headers: administrator.create_new_auth_token

      body = response.parsed_body['payload']
      expect(body.keys).to contain_exactly(
        'id', 'reference', 'reference_number', 'title', 'description', 'category', 'status', 'priority',
        'label_list', 'conversation_id', 'conversation_display_id', 'contact_id', 'inbox_id', 'assignee_id',
        'team_id', 'created_by_id', 'source_type', 'source_id', 'sla', 'last_activity_at', 'resolved_at',
        'closed_at', 'created_at', 'updated_at'
      )
      expect(response.body).not_to match(/token|secret|password|provider_config/i)
    end
  end

  describe 'notes and history' do
    let(:ticket) { create(:support_ticket, account: account) }

    it 'adds an internal note and returns it in the history' do
      post "/api/v1/accounts/#{account.id}/support/tickets/#{ticket.id}/events",
           params: { event: { body: 'Called the customer, no answer' } }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:created)
      get "/api/v1/accounts/#{account.id}/support/tickets/#{ticket.id}/events",
          headers: administrator.create_new_auth_token
      types = response.parsed_body['payload'].pluck('event_type')
      expect(types).to include('note')
    end

    it 'refuses an empty note' do
      post "/api/v1/accounts/#{account.id}/support/tickets/#{ticket.id}/events",
           params: { event: { body: '' } }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Only `note` is creatable through the API: every other event type is written by the service that performed
    # the change, so a client cannot fabricate a status change that never happened.
    it 'ignores an attempt to post any other event type' do
      post "/api/v1/accounts/#{account.id}/support/tickets/#{ticket.id}/events",
           params: { event: { body: 'x', event_type: 'resolved' } }, headers: administrator.create_new_auth_token

      expect(Support::TicketEvent.last.event_type).to eq('note')
    end

    it 'refuses history for a case the caller may not see' do
      someone_elses = create(:support_ticket, account: account, assignee: administrator)
      get "/api/v1/accounts/#{account.id}/support/tickets/#{someone_elses.id}/events",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end
end
