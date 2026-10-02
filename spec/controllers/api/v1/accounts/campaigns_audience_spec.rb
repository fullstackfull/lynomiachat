require 'rails_helper'

# Shared audiences as campaign recipients through Chatwoot's campaigns API (docs/campaigns/02-recipients.md).
RSpec.describe 'Campaigns API with shared audiences', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:sms_inbox) { create(:inbox, account: account, channel: create(:channel_sms, account: account)) }
  let(:label) { create(:label, account: account) }
  let(:query) { { 'payload' => [{ 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['vip.example'] }] } }
  let(:shared) { create(:custom_filter, account: account, user: administrator, filter_type: :contact, shared: true, name: 'VIP', query: query) }
  let(:personal) { create(:custom_filter, account: account, user: administrator, filter_type: :contact, name: 'Mine', query: query) }
  let(:foreign) { create(:custom_filter, account: create(:account), user: nil, filter_type: :contact, shared: true, name: 'Theirs', query: query) }
  let(:campaign_params) { { title: 'Eid offer', message: 'Hello', inbox_id: sms_inbox.id, scheduled_at: 1.day.from_now } }

  it 'creates a campaign whose audience references labels and a shared audience, never its conditions' do
    post "/api/v1/accounts/#{account.id}/campaigns",
         params: campaign_params.merge(audience: [{ type: 'Label', id: label.id }, { type: 'Audience', id: shared.id }]),
         headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['audience']).to eq([{ 'type' => 'Label', 'id' => label.id }, { 'type' => 'Audience', 'id' => shared.id }])
    expect(account.campaigns.last.audience.to_json).not_to include('vip.example')
  end

  it 'refuses personal audiences and audiences of another account with 422, creating nothing' do
    [personal, foreign].each do |audience|
      post "/api/v1/accounts/#{account.id}/campaigns",
           params: campaign_params.merge(audience: [{ type: 'Audience', id: audience.id }]),
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include(I18n.t('errors.campaigns.audience_not_shared'))
    end
    expect(account.campaigns.count).to eq(0)
  end

  it 'refuses the same on update' do
    campaign = create(:campaign, account: account, inbox: sms_inbox, audience: [{ type: 'Label', id: label.id }])

    patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
          params: { audience: [{ type: 'Audience', id: foreign.id }] },
          headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(campaign.reload.audience).to eq([{ 'type' => 'Label', 'id' => label.id }])
  end

  it 'keeps campaigns for administrators only' do
    post "/api/v1/accounts/#{account.id}/campaigns",
         params: campaign_params.merge(audience: [{ type: 'Audience', id: shared.id }]),
         headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
