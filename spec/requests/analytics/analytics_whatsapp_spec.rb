require 'rails_helper'

RSpec.describe 'Analytics WhatsApp delivery', type: :request do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'America/New_York') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:range) { { since: '2026-10-01', until: '2026-10-07' } }

  def get_whatsapp(params = range, as: administrator, for_account: account)
    get "/api/v1/accounts/#{for_account.id}/analytics/whatsapp",
        params: params, headers: as.create_new_auth_token
  end

  describe 'authorization' do
    it 'refuses an unauthenticated caller' do
      get "/api/v1/accounts/#{account.id}/analytics/whatsapp", params: range
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an agent, following the reporting permission' do
      get_whatsapp(as: agent)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an administrator of another account on this account's endpoint" do
      get_whatsapp(as: other_administrator)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'payload' do
    before do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       status: :read, created_at: Time.utc(2026, 10, 2, 10, 0),
                       additional_attributes: { 'template_params' => { 'name' => 'order_delivered', 'language' => 'en_US' } })
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       status: :failed, created_at: Time.utc(2026, 10, 2, 11, 0),
                       content_attributes: { external_error: '131049: Message undeliverable' })
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       status: :delivered, created_at: Time.utc(2026, 10, 2, 12, 0),
                       content_attributes: { external_echo: true })
    end

    it 'returns the shared envelope' do
      get_whatsapp
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.keys).to match_array(%w[meta kpis series breakdowns])
      expect(response.parsed_body['meta']).to include('family' => 'whatsapp', 'timezone' => 'Asia/Kuwait')
    end

    it 'reports the counts with the echo excluded and separately named' do
      get_whatsapp
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['messages_sent']['value']).to eq(2)
      expect(kpis['delivered']['value']).to eq(1)
      expect(kpis['read']['value']).to eq(1)
      expect(kpis['failed']['value']).to eq(1)
      expect(kpis['coexistence_echoes']['value']).to eq(1)
    end

    it 'reports rates as percentages' do
      get_whatsapp
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['delivery_rate']).to include('value' => 50.0, 'unit' => 'percent')
      expect(kpis['failure_rate']).to include('value' => 50.0, 'unit' => 'percent')
    end

    it 'defaults the breakdown to template' do
      get_whatsapp
      breakdown = response.parsed_body['breakdowns'].first

      expect(breakdown).to include('key' => 'by_template', 'dimension' => 'template')
      expect(breakdown['rows'].first).to include('label' => 'order_delivered (en_US)', 'value' => 1)
    end

    it 'breaks down failures by the refusal Meta gave' do
      get_whatsapp(range.merge(breakdown_by: 'failure'))
      breakdown = response.parsed_body['breakdowns'].first

      expect(breakdown['dimension']).to eq('failure')
      expect(breakdown['rows'].first).to include('label' => '131049: Message undeliverable', 'value' => 1)
    end

    it 'says the source is raw and names why no rollup was used' do
      get_whatsapp
      expect(response.parsed_body['meta']).to include('source' => 'raw', 'source_reason' => 'no_rollup_metric')
    end
  end

  describe 'rejected requests' do
    it 'refuses an unknown breakdown with 422 and the allowed list' do
      get_whatsapp(range.merge(breakdown_by: 'agent'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('template, inbox, failure')
    end

    it 'refuses a filter this family does not support' do
      get_whatsapp(range.merge(team_id: 1))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('team_id')
    end

    it 'refuses a template id that belongs to another account' do
      foreign = Whatsapp::MessageTemplate.create!(account: other_account, business_account_id: 'WABA9',
                                                  name: 'not_yours', language: 'en', category: 'UTILITY',
                                                  components: [{ 'type' => 'BODY', 'text' => 'x' }])

      get_whatsapp(range.merge(template_id: foreign.id))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('template_id')
    end
  end
end
