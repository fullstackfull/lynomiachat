require 'rails_helper'

RSpec.describe 'Analytics flows', type: :request do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'America/New_York') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil, name: 'Welcome') }
  let(:version) do
    FlowVersion.create!(account: account, agent_bot: bot, version: 1, status: :published,
                        graph: { 'nodes' => [], 'edges' => [] })
  end
  let(:range) { { since: '2026-10-01', until: '2026-10-07' } }

  def get_flows(params = range, as: administrator, for_account: account)
    get "/api/v1/accounts/#{for_account.id}/analytics/flows",
        params: params, headers: as.create_new_auth_token
  end

  def session(status:, finished: Time.utc(2026, 10, 2, 10, 0), failure_code: nil, end_reason: nil)
    FlowSession.create!(
      account: account, agent_bot: bot, flow_version: version, status: status, steps_count: 5,
      conversation: create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account)),
      failure_code: failure_code, finished_at: finished, created_at: Time.utc(2026, 10, 2, 9, 0),
      context: end_reason ? { 'end_reason' => end_reason } : {}
    )
  end

  describe 'authorization' do
    it 'refuses an unauthenticated caller' do
      get "/api/v1/accounts/#{account.id}/analytics/flows", params: range
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an agent, following the reporting permission' do
      get_flows(as: agent)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an administrator of another account on this account's endpoint" do
      get_flows(as: other_administrator)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'payload' do
    before do
      session(status: :completed)
      session(status: :failed, failure_code: 'step_limit')
      session(status: :handed_off, end_reason: 'Care asked')
      session(status: :waiting, finished: nil)
    end

    it 'returns the shared envelope' do
      get_flows
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']).to include('family' => 'flows', 'timezone' => 'Asia/Kuwait')
    end

    it 'reports the session lifecycle' do
      get_flows
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['sessions_started']['value']).to eq(4)
      expect(kpis['sessions_completed']['value']).to eq(1)
      expect(kpis['sessions_failed']['value']).to eq(1)
      expect(kpis['handed_off']['value']).to eq(1)
    end

    it 'reports duration in seconds and the live count as current state' do
      get_flows
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['average_duration']).to include('value' => 3600, 'unit' => 'seconds')
      expect(kpis['live_now']).to include('value' => 1, 'kind' => 'current_state')
    end

    it 'breaks down endings by bot by default' do
      get_flows
      breakdown = response.parsed_body['breakdowns'].first

      expect(breakdown).to include('key' => 'by_bot', 'dimension' => 'bot')
      expect(breakdown['rows'].first).to include('label' => 'Welcome', 'value' => 3)
    end

    it 'breaks down failures by the recorded code' do
      get_flows(range.merge(breakdown_by: 'failure'))

      expect(response.parsed_body['breakdowns'].first['rows'].first)
        .to include('label' => 'step_limit', 'value' => 1)
    end

    it 'breaks down handoffs and cancellations by the recorded reason' do
      get_flows(range.merge(breakdown_by: 'end_reason'))

      expect(response.parsed_body['breakdowns'].first['rows'].first)
        .to include('label' => 'Care asked', 'value' => 1)
    end
  end

  describe 'rejected requests' do
    it 'refuses an unknown breakdown with 422 and the allowed list' do
      get_flows(range.merge(breakdown_by: 'node'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('bot, status, failure, end_reason')
    end

    it 'refuses an inbox id that belongs to another account' do
      foreign = create(:inbox, account: other_account)

      get_flows(range.merge(inbox_id: foreign.id))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('inbox_id')
    end
  end
end
