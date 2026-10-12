require 'rails_helper'

RSpec.describe 'Platform Support tenant tickets API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/platform_support" }

  let(:ticket) do
    PlatformSupport::TicketCreation.new(
      account: account, reporter: administrator,
      attributes: { category: 'whatsapp', subject: 'Template stuck in review', description: 'Pending since Sunday',
                    priority: 'high' }
    ).perform
  end

  def payload
    response.parsed_body['payload']
  end

  describe 'GET /tickets' do
    it 'needs authentication' do
      get "#{base}/tickets"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'answers the meta/payload envelope with the three counts' do
      ticket
      get "#{base}/tickets", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']).to include('current_page' => 1, 'total_entries' => 1, 'per_page' => 25)
      expect(response.parsed_body['meta']['counts']).to eq('open' => 1, 'closed' => 0, 'unread' => 0)
    end

    it 'has no feature gate: the complaints channel is never sold' do
      get "#{base}/tickets", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(account.reload.feature_enabled?('lynomia_support_tickets')).to be(false)
    end

    it 'answers 422 for an unknown filter value rather than a page that looks like an answer' do
      get "#{base}/tickets", params: { status: ['escalated'] }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('escalated')
    end

    it 'answers 422 for a per_page outside the range' do
      get "#{base}/tickets", params: { per_page: '500' }, headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'the ticket payload' do
    before do
      ticket
      get "#{base}/tickets/#{ticket.id}", headers: administrator.create_new_auth_token
    end

    it 'carries exactly the keys the contract lists, and no others' do
      expect(payload.keys).to match_array(
        %w[id reference reference_number subject description category status priority reporter_name unread
           message_count attachment_count last_activity_at last_operator_message_at resolved_at closed_at
           created_at updated_at]
      )
    end

    it 'omits the assignee, the SLA, every due and breach stamp, the plan snapshot and the notes' do
      expect(payload.keys).not_to include(
        'assignee_id', 'assignee_name', 'sla', 'first_response_due_at', 'resolution_due_at',
        'first_responded_at', 'first_response_breached_at', 'resolution_breached_at', 'sla_paused_at',
        'sla_paused_seconds', 'plan_id_at_creation', 'plan_name_at_creation',
        'subscription_status_at_creation', 'internal_notes', 'links'
      )
    end

    it 'renders the reference, the thread totals and unix-second timestamps' do
      expect(payload).to include('reference' => ticket.reference, 'message_count' => 1, 'attachment_count' => 0,
                                 'unread' => false, 'status' => 'open', 'priority' => 'high')
      expect(payload['created_at']).to eq(ticket.created_at.to_i)
    end
  end

  describe 'GET /tickets/:id' do
    it 'resolves a LYN- reference as well as an id' do
      ticket
      get "#{base}/tickets/#{ticket.reference}", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(payload['id']).to eq(ticket.id)
    end

    it 'answers 404 for a reference that does not exist' do
      get "#{base}/tickets/LYN-999999", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /tickets' do
    it 'opens the ticket, always open, and returns 201 with the ticket' do
      post "#{base}/tickets",
           params: { ticket: { category: 'billing', subject: 'Invoice is wrong', description: 'Charged twice',
                               priority: 'urgent', status: 'resolved' } },
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:created)
      expect(payload).to include('status' => 'open', 'priority' => 'urgent', 'category' => 'billing')
      expect(payload['reference']).to match(/\ALYN-\d{6}\z/)
    end

    it 'ignores every server-owned field a client tries to set' do
      post "#{base}/tickets",
           params: { ticket: { category: 'bug', subject: 'A bug', description: 'Details',
                               reference_number: 9999, account_id: 123, assignee_id: 7, sla_policy_id: 3,
                               reporter_name: 'Somebody Else', resolution_due_at: 1.day.from_now.to_i } },
           headers: administrator.create_new_auth_token

      created = PlatformSupport::Ticket.last
      expect(created).to have_attributes(account_id: account.id, assignee_id: nil, sla_policy_id: nil,
                                         resolution_due_at: nil, reporter_name: administrator.available_name)
      expect(created.reference_number).not_to eq(9999)
    end

    it 'answers 422 for a category outside the eleven' do
      post "#{base}/tickets",
           params: { ticket: { category: 'technical', subject: 'A thing', description: 'Details' } },
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('technical')
    end

    it 'answers 422 for an unknown priority' do
      post "#{base}/tickets",
           params: { ticket: { category: 'bug', subject: 'A thing', description: 'Details', priority: 'blocker' } },
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'answers 422 for an empty description, which is the one spam control a rate limit cannot give' do
      post "#{base}/tickets", params: { ticket: { category: 'bug', subject: 'A thing', description: '' } },
                              headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(PlatformSupport::Ticket.count).to eq(0)
    end

    it 'answers 422 for a missing subject' do
      post "#{base}/tickets", params: { ticket: { category: 'bug', description: 'Details' } },
                              headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'lets an agent open one, and attributes it to them' do
      post "#{base}/tickets", params: { ticket: { category: 'bug', subject: 'A thing', description: 'Details' } },
                              headers: agent.create_new_auth_token

      expect(response).to have_http_status(:created)
      expect(PlatformSupport::Ticket.last).to have_attributes(reporter_id: agent.id)
    end
  end

  describe 'PATCH /tickets/:id' do
    it 'accepts a priority change, because it is a request rather than a promise' do
      patch "#{base}/tickets/#{ticket.id}", params: { ticket: { priority: 'low' } },
                                            headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(payload['priority']).to eq('low')
      expect(ticket.reload.events.pluck(:event_type)).to include('priority_changed')
    end

    it 'closes a resolved ticket, which is the customer\'s only status edge' do
      ticket.update!(status: :resolved, resolved_at: Time.current)
      patch "#{base}/tickets/#{ticket.id}", params: { ticket: { status: 'closed' } },
                                            headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(ticket.reload).to have_attributes(status: 'closed')
      expect(ticket.resolved_at).to be_present
    end

    it 'answers 422 when the customer asks for any other status edge' do
      patch "#{base}/tickets/#{ticket.id}", params: { ticket: { status: 'in_progress' } },
                                            headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ticket.reload.status).to eq('open')
    end

    it 'answers 422 for a status that is not a status at all' do
      patch "#{base}/tickets/#{ticket.id}", params: { ticket: { status: 'escalated' } },
                                            headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'does not apply a category, subject or description change: recategorising is Lynomia\'s triage' do
      patch "#{base}/tickets/#{ticket.id}",
            params: { ticket: { category: 'billing', subject: 'Rewritten', description: 'Rewritten' } },
            headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(ticket.reload).to have_attributes(category: 'whatsapp', subject: 'Template stuck in review',
                                               description: 'Pending since Sunday')
    end
  end

  describe 'POST /tickets/:id/mark_viewed' do
    it 'stamps the view and clears the unread dot' do
      ticket.update!(last_operator_message_at: Time.current)
      expect(ticket.reload).to be_unread

      post "#{base}/tickets/#{ticket.id}/mark_viewed", headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(ticket.reload).not_to be_unread
    end

    it 'is not reachable by a GET, so no link or prefetch can mark replies read' do
      expect { Rails.application.routes.recognize_path("#{base}/tickets/#{ticket.id}/mark_viewed", method: :get) }
        .to raise_error(ActionController::RoutingError)

      expect(Rails.application.routes.recognize_path("#{base}/tickets/#{ticket.id}/mark_viewed", method: :post))
        .to include(controller: 'api/v1/accounts/platform_support/tickets', action: 'mark_viewed')
    end
  end

  # The serializer's `message_count` and `attachment_count` are the N+1 hazard on this endpoint: a per-row
  # COUNT would make the page cost grow with the page. PlatformSupport::ThreadTotals does two grouped counts
  # for the whole page instead, so the query count is flat as tickets grow.
  describe 'the list query budget' do
    def queries_for_index
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION]) }
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        get "#{base}/tickets", headers: administrator.create_new_auth_token
      end
      count
    end

    def open_tickets(number)
      number.times do |index|
        created = PlatformSupport::TicketCreation.new(
          account: account, reporter: administrator,
          attributes: { category: 'bug', subject: "Ticket #{index}", description: 'Details' }
        ).perform
        created.messages.create!(
          PlatformSupport::Message.author_attributes_for(administrator).merge(body: 'Another message')
        )
      end
    end

    it 'costs the same for twelve tickets as for two' do
      open_tickets(2)
      administrator.create_new_auth_token
      small = queries_for_index

      open_tickets(10)
      large = queries_for_index

      expect(response.parsed_body['payload'].length).to eq(12)
      expect(large).to eq(small)
      Rails.logger.info("platform_support tenant list query budget: 2 tickets #{small}, 12 tickets #{large}")
    end
  end

  it 'offers no destroy route anywhere: a ticket is closed, never deleted' do
    delete "#{base}/tickets/#{ticket.id}", headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:not_found)
    expect(ticket.reload).to be_persisted
  end

  it 'offers no internal notes route at all: not a filtered one, not a 403 one, none' do
    get "#{base}/tickets/#{ticket.id}/internal_notes", headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:not_found)
    expect(Rails.application.routes.routes.map { |route| route.path.spec.to_s }.grep(/internal_note/)).to be_empty
  end
end
