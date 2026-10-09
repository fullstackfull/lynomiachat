require 'rails_helper'

RSpec.describe 'Analytics overview', type: :request do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'America/New_York') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:range) { { since: '2026-10-01', until: '2026-10-07' } }

  def get_overview(params = range, as: administrator, for_account: account)
    get "/api/v1/accounts/#{for_account.id}/analytics/overview",
        params: params, headers: as.create_new_auth_token
  end

  describe 'authorization' do
    it 'refuses an unauthenticated caller' do
      get "/api/v1/accounts/#{account.id}/analytics/overview", params: range
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an agent, following the reporting permission' do
      get_overview(as: agent)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an administrator of another account on this account's endpoint" do
      get_overview(as: other_administrator)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'payload' do
    before do
      create(:conversation, account: account, inbox: inbox, contact: contact,
                            status: :open, created_at: Time.utc(2026, 10, 1, 10, 0))
      create(:conversation, account: account, inbox: inbox, contact: contact,
                            status: :resolved, created_at: Time.utc(2026, 10, 2, 10, 0))
    end

    it 'returns the P8.1 envelope with meta, kpis, series and breakdowns' do
      get_overview
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.keys).to match_array(%w[meta kpis series breakdowns])
    end

    it 'carries the account timezone and the resolved window in meta' do
      get_overview
      expect(response.parsed_body['meta']).to include(
        'family' => 'conversations', 'timezone' => 'Asia/Kuwait',
        'starts_at' => '2026-09-30T21:00:00Z', 'ends_at' => '2026-10-07T21:00:00Z'
      )
    end

    it 'labels the backlog as current state and the rest as events' do
      get_overview
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['unresolved_backlog']['kind']).to eq('current_state')
      expect(kpis['conversations_created']['kind']).to eq('event')
      expect(kpis['avg_resolution_time']['unit']).to eq('seconds')
    end

    it 'reports every conversation and message metric' do
      get_overview
      keys = response.parsed_body['kpis'].map { |kpi| kpi['key'] }

      expect(keys).to match_array(%w[
                                    conversations_created conversations_resolved conversations_reopened
                                    avg_first_response_time avg_resolution_time inbound_messages outbound_messages
                                    unresolved_backlog
                                  ])
    end

    it 'emits one series point per bucket' do
      get_overview
      series = response.parsed_body['series'].index_by { |entry| entry['key'] }

      expect(series['conversations_created']['points'].length).to eq(7)
      expect(series['conversations_created']['points'].sum { |point| point['value'] }).to eq(2)
    end

    it 'says which source answered and why, rather than leaving it implied' do
      get_overview
      expect(response.parsed_body['meta']).to include('source' => 'raw', 'source_reason' => 'feature_disabled')
    end

    it 'breaks down by inbox by default' do
      get_overview
      breakdown = response.parsed_body['breakdowns'].first
      expect(breakdown).to include('key' => 'by_inbox', 'dimension' => 'inbox')
      expect(breakdown['rows'].first).to include('label' => inbox.name, 'value' => 2)
    end

    it 'accepts another breakdown dimension' do
      get_overview(range.merge(breakdown_by: 'channel'))
      expect(response.parsed_body['breakdowns'].first['dimension']).to eq('channel')
    end

    it 'refuses an unknown breakdown dimension with 422' do
      get_overview(range.merge(breakdown_by: 'moon_phase'))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('inbox, channel, team, agent')
    end
  end

  describe 'tenant isolation' do
    it "never counts another account's conversations" do
      create(:conversation, account: other_account,
                            inbox: create(:inbox, account: other_account),
                            contact: create(:contact, account: other_account),
                            status: :open, created_at: Time.utc(2026, 10, 1, 10, 0))

      get_overview
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }
      expect(kpis['conversations_created']['value']).to eq(0)
      expect(kpis['unresolved_backlog']['value']).to eq(0)
    end

    it 'refuses a filter id belonging to another account' do
      foreign_inbox = create(:inbox, account: other_account)
      get_overview(range.merge(inbox_id: foreign_inbox.id))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('inbox_id')
    end
  end

  describe 'empty state' do
    it 'reports empty rather than failing when the account has no data' do
      get_overview
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']).to include('empty' => true, 'partial' => false)
    end
  end

  describe 'determinism' do
    before do
      create(:conversation, account: account, inbox: inbox, contact: contact,
                            status: :open, created_at: Time.utc(2026, 10, 1, 22, 0))
    end

    it 'gives two administrators of the same account the same body' do
      second = create(:user, account: account, role: :administrator)
      get_overview
      first_body = response.body
      get_overview(as: second)

      expect(response.body).to eq(first_body)
    end

    it 'ignores a client timezone and keeps the 22:00 UTC conversation on the local next day' do
      get_overview(range.merge(timezone: 'America/Los_Angeles', timezone_offset: '-7'))
      series = response.parsed_body['series'].index_by { |entry| entry['key'] }
      points = series['conversations_created']['points'].index_by { |point| point['bucket'] }

      expect(response.parsed_body['meta']['timezone']).to eq('Asia/Kuwait')
      expect(points['2026-10-02']['value']).to eq(1)
      expect(points['2026-10-01']['value']).to eq(0)
    end
  end
end
