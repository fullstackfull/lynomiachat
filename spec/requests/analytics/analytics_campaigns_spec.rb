require 'rails_helper'

RSpec.describe 'Analytics campaigns', type: :request do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'America/New_York') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago) }
  let(:range) { { since: '2026-10-01', until: '2026-10-07' } }

  def get_campaigns(params = range, as: administrator, for_account: account)
    get "/api/v1/accounts/#{for_account.id}/analytics/campaigns",
        params: params, headers: as.create_new_auth_token
  end

  describe 'authorization' do
    it 'refuses an unauthenticated caller' do
      get "/api/v1/accounts/#{account.id}/analytics/campaigns", params: range
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an agent, following the reporting permission' do
      get_campaigns(as: agent)
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an administrator of another account on this account's endpoint" do
      get_campaigns(as: other_administrator)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'payload' do
    before do
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox,
                                contact: create(:contact, account: account), created_at: Time.utc(2026, 10, 2, 10, 0),
                                status: :read, source_id: 'wamid.a', sent_at: Time.utc(2026, 10, 2, 10, 1),
                                delivered_at: Time.utc(2026, 10, 2, 10, 2), read_at: Time.utc(2026, 10, 2, 10, 3))
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox,
                                contact: create(:contact, account: account), created_at: Time.utc(2026, 10, 2, 10, 0),
                                status: :failed, failed_at: Time.utc(2026, 10, 2, 10, 2), error_code: '131049')
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox,
                                contact: create(:contact, account: account), created_at: Time.utc(2026, 10, 2, 10, 0),
                                status: :skipped, error_message: 'Contact has no phone number')
    end

    it 'returns the shared envelope' do
      get_campaigns
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.keys).to match_array(%w[meta kpis series breakdowns])
      expect(response.parsed_body['meta']).to include('family' => 'campaigns', 'timezone' => 'Asia/Kuwait')
    end

    it 'reports what the period addressed' do
      get_campaigns
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['campaigns_run']['value']).to eq(1)
      expect(kpis['recipients_targeted']['value']).to eq(3)
      expect(kpis['sent']['value']).to eq(1)
      expect(kpis['pending']['value']).to eq(0)
    end

    it 'reports each outcome' do
      get_campaigns
      kpis = response.parsed_body['kpis'].index_by { |kpi| kpi['key'] }

      expect(kpis['delivered']['value']).to eq(1)
      expect(kpis['read']['value']).to eq(1)
      expect(kpis['failed']['value']).to eq(1)
      expect(kpis['skipped']['value']).to eq(1)
    end

    it 'defaults the breakdown to campaign' do
      get_campaigns
      breakdown = response.parsed_body['breakdowns'].first

      expect(breakdown).to include('key' => 'by_campaign', 'dimension' => 'campaign')
      expect(breakdown['rows'].first).to include('label' => campaign.title, 'value' => 3)
    end

    it 'breaks down skips by the reason recorded' do
      get_campaigns(range.merge(breakdown_by: 'skip_reason'))
      breakdown = response.parsed_body['breakdowns'].first

      expect(breakdown['rows'].first).to include('label' => 'Contact has no phone number', 'value' => 1)
    end
  end

  describe 'rejected requests' do
    it 'refuses an unknown breakdown with 422 and the allowed list' do
      get_campaigns(range.merge(breakdown_by: 'template'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('campaign, audience, failure, skip_reason')
    end

    it 'refuses a campaign id that belongs to another account' do
      foreign = create(:campaign, account: other_account, campaign_type: :one_off, scheduled_at: 1.hour.ago)

      get_campaigns(range.merge(campaign_id: foreign.id))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('campaign_id')
    end
  end
end
