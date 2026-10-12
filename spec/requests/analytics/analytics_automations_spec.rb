require 'rails_helper'

RSpec.describe 'Analytics automations', type: :request do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'America/New_York') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account)) }
  let(:rule) do
    create(:automation_rule, account: account, name: 'Chase the customer', event_name: 'conversation_resolved',
                             execution_delay: 30)
  end
  let(:range) { { since: 6.days.ago.to_date.to_s, until: Date.current.to_s } }

  def get_automations(params = range, as: administrator, for_account: account)
    get "/api/v1/accounts/#{for_account.id}/analytics/automations",
        params: params, headers: as.create_new_auth_token
  end

  def execution(status:, skip_reason: nil)
    AutomationRulePendingExecution.create!(
      automation_rule: rule, conversation: conversation, account_id: account.id,
      episode_key: "status:#{SecureRandom.hex(6)}", due_at: 1.hour.from_now, status: status,
      skip_reason: skip_reason, created_at: 3.days.ago, updated_at: 3.days.ago
    )
  end

  describe 'authorization' do
    it 'refuses an unauthenticated caller' do
      get "/api/v1/accounts/#{account.id}/analytics/automations", params: range
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an agent, following the reporting permission' do
      get_automations(as: agent)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an administrator of another account on this account's endpoint" do
      get_automations(as: other_administrator)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'payload' do
    before do
      execution(status: :executed)
      execution(status: :skipped, skip_reason: 'episode_ended')
    end

    it 'returns the shared envelope' do
      get_automations
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']).to include('family' => 'automations', 'timezone' => 'Asia/Kuwait')
    end

    it 'reports the delayed-rule outcomes' do
      get_automations
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['executed']['value']).to eq(1)
      expect(kpis['skipped']['value']).to eq(1)
      expect(kpis['execution_rate']).to include('value' => 50.0, 'unit' => 'percent')
    end

    it 'labels the queue readings as current state' do
      get_automations
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['awaiting_now']['kind']).to eq('current_state')
      expect(kpis['stranded_now']['kind']).to eq('current_state')
      expect(kpis['executed']['kind']).to eq('event')
    end

    it 'breaks down skips by the recorded reason' do
      get_automations(range.merge(breakdown_by: 'skip_reason'))
      breakdown = response.parsed_body['breakdowns'].first

      expect(breakdown['rows'].first).to include('label' => 'episode_ended', 'value' => 1)
    end
  end

  describe 'what the response says it cannot cover' do
    it 'warns that immediate rules leave no execution record' do
      create(:automation_rule, account: account, event_name: 'conversation_created', execution_delay: nil)

      get_automations

      expect(response.parsed_body['meta']['partial']).to be(true)
      expect(response.parsed_body['meta']['warnings'])
        .to include('scope' => 'immediate_rules', 'reason' => 'no_execution_record')
    end

    it 'does not warn when every rule is delayed' do
      rule

      get_automations

      expect(response.parsed_body['meta']['warnings'].pluck('scope')).not_to include('immediate_rules')
    end

    it 'warns when the range reaches past the retention window' do
      get_automations({ since: 90.days.ago.to_date.to_s, until: Date.current.to_s, group_by: 'month' })

      expect(response.parsed_body['meta']['warnings'])
        .to include('scope' => 'retention_window', 'reason' => 'terminal_rows_purged_after_30_days')
    end
  end

  describe 'rejected requests' do
    it 'refuses an unknown breakdown with 422 and the allowed list' do
      get_automations(range.merge(breakdown_by: 'inbox'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('rule, skip_reason, status')
    end

    it 'refuses a rule id that belongs to another account' do
      foreign = create(:automation_rule, account: other_account, event_name: 'conversation_created')

      get_automations(range.merge(automation_rule_id: foreign.id))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('automation_rule_id')
    end
  end
end
