require 'rails_helper'

RSpec.describe 'Ticket analytics', type: :request do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def get_tickets(params = {}, as: administrator, for_account: account)
    get "/api/v1/accounts/#{for_account.id}/analytics/tickets",
        params: { since: '2026-10-01', until: '2026-10-07' }.merge(params), headers: as.create_new_auth_token
  end

  describe 'authorization' do
    # Account-wide reporting, so it follows the report permission like every other analytics family, not the
    # per-case one.
    it 'is administrator only' do
      get_tickets(as: agent)
      expect(response).to have_http_status(:unauthorized)

      get_tickets
      expect(response).to have_http_status(:success)
    end

    it 'refuses an administrator of another account' do
      get_tickets(as: create(:user, account: other_account, role: :administrator))
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'payload' do
    before do
      create(:support_ticket, account: account, created_at: Time.utc(2026, 10, 2, 10, 0), priority: :urgent)
      create(:support_ticket, account: other_account, created_at: Time.utc(2026, 10, 2, 10, 0))
    end

    it 'reports the counts, the series and the breakdown, scoped to this account' do
      get_tickets

      body = response.parsed_body
      kpis = body['kpis'].index_by { |kpi| kpi['key'] }
      expect(kpis['tickets_created']['value']).to eq(1)
      expect(kpis['average_resolution_time']).not_to have_key('value')
      expect(body['series'].pluck('key')).to include('tickets_created', 'tickets_resolved', 'resolution_breaches')
      expect(body['breakdowns'].first['rows'].first).to include('id' => 'urgent', 'value' => 1)
    end

    it 'labels the three readings taken now so a screen cannot plot them as history' do
      get_tickets

      current = response.parsed_body['kpis'].select { |kpi| kpi['kind'] == 'current_state' }
      expect(current.pluck('key')).to contain_exactly('open_now', 'overdue_now', 'unassigned_now')
    end

    # A case with no policy can never breach, so a zero breach count beside ungoverned cases must not read as
    # "nothing was ever late".
    it 'warns when some active cases have no SLA policy at all' do
      get_tickets

      expect(response.parsed_body['meta']['warnings'])
        .to include('scope' => 'sla', 'reason' => 'active_cases_without_a_policy')
    end

    # A warning that is always present is a banner an operator learns to ignore.
    it 'does not warn when every active case is governed' do
      policy = create(:support_sla_policy, account: account)
      account.support_tickets.find_each { |ticket| ticket.update!(sla_policy: policy) }

      get_tickets

      expect(response.parsed_body['meta']['warnings']).to be_empty
      expect(response.parsed_body['meta']['partial']).to be(false)
    end

    it 'cuts its buckets in the account timezone, not the viewer timezone' do
      get_tickets

      expect(response.parsed_body['meta']['timezone']).to eq('Asia/Kuwait')
    end
  end

  describe 'filters' do
    it 'refuses a team from another account with 422' do
      get_tickets({ team_id: create(:team, account: other_account).id })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refuses an unsupported breakdown with 422 naming the allowed set' do
      get_tickets({ breakdown_by: 'inbox' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('priority')
    end
  end
end
