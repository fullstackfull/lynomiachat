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

  describe 'audience dependency' do
    let(:filters) { "/api/v1/accounts/#{account.id}/custom_filters" }
    let!(:campaign) { create(:campaign, account: account, inbox: sms_inbox, audience: [{ type: 'Audience', id: shared.id }]) }

    it 'refuses to delete or unshare an audience a campaign still to send uses, and says how many' do
      [:active, :processing].each do |status|
        campaign.update!(campaign_status: status)

        delete "#{filters}/#{shared.id}", headers: administrator.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.custom_filters.used_by_campaigns', count: 1))

        patch "#{filters}/#{shared.id}", params: { custom_filter: { shared: false } }, headers: administrator.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(shared.reload.shared).to be(true)
    end

    it 'reports automation rules and campaigns together' do
      rule = account.automation_rules.new(name: 'VIP', event_name: 'conversation_created', actions: [],
                                          conditions: [{ 'attribute_key' => 'contact_audience', 'filter_operator' => 'equal_to',
                                                         'values' => [shared.id], 'query_operator' => nil }])
      rule.save!(validate: false)

      delete "#{filters}/#{shared.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response.parsed_body['error']).to eq("#{I18n.t('errors.custom_filters.used_by_automation', count: 1)} " \
                                                  "#{I18n.t('errors.custom_filters.used_by_campaigns', count: 1)}")

      get "#{filters}/#{shared.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('automation_rules_count' => 1, 'campaigns_count' => 1)
    end

    it 'releases the audience once the campaign is sent or deleted' do
      campaign.update!(campaign_status: :completed)
      get "#{filters}/#{shared.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response.parsed_body['campaigns_count']).to eq(0)

      other = create(:custom_filter, account: account, user: administrator, filter_type: :contact, shared: true, name: 'Other', query: query)
      scheduled = create(:campaign, account: account, inbox: sms_inbox, audience: [{ type: 'Audience', id: other.id }])
      delete "/api/v1/accounts/#{account.id}/campaigns/#{scheduled.display_id}", headers: administrator.create_new_auth_token, as: :json

      [shared, other].each do |audience|
        delete "#{filters}/#{audience.id}", headers: administrator.create_new_auth_token, as: :json
        expect(response).to have_http_status(:no_content)
      end
    end

    it 'counts only the campaigns of the audience\'s own account' do
      foreign_campaign = build(:campaign, account: create(:account), campaign_type: :one_off, audience: [{ type: 'Audience', id: shared.id }])
      foreign_campaign.save!(validate: false)
      campaign.destroy!
      expect(Campaign.one_off.active.where('audience @> ?', [{ type: 'Audience', id: shared.id }].to_json)).to eq([foreign_campaign])

      delete "#{filters}/#{shared.id}", headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
    end
  end

  describe 'POST /campaigns/audience_preview' do
    let(:preview) { "/api/v1/accounts/#{account.id}/campaigns/audience_preview" }
    let(:gulf) do
      create(:custom_filter, account: account, user: administrator, filter_type: :contact, shared: true, name: 'Gulf',
                             query: { 'payload' => [{ 'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['sa'] }] })
    end

    before do
      create(:contact, account: account, email: 'layla@vip.example', additional_attributes: { 'country_code' => 'SA' }).update_labels([label.title])
      create(:contact, account: account, email: 'omar@vip.example')
      create(:contact, account: account, email: 'sara@mail.example').update_labels([label.title])
      create(:contact, account: account, email: 'noor@mail.example', additional_attributes: { 'country_code' => 'SA' })
      create(:contact, account: account, email: 'ali@mail.example')
      create(:contact, account: create(:account), email: 'twin@vip.example', additional_attributes: { 'country_code' => 'SA' })
    end

    it 'counts each contact once across labels and shared audiences, in the account only, calling nothing outside' do
      counts = [
        [{ type: 'Label', id: label.id }],
        [{ type: 'Audience', id: shared.id }],
        [{ type: 'Label', id: label.id }, { type: 'Audience', id: shared.id }],
        [{ type: 'Label', id: label.id }, { type: 'Audience', id: shared.id }, { type: 'Audience', id: gulf.id }]
      ].map do |audience|
        post preview, params: { audience: audience }, headers: administrator.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
        response.parsed_body['count']
      end

      expect(counts).to eq([2, 2, 3, 4])
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'counts what the campaign would send to' do
      audience = [{ type: 'Label', id: label.id }, { type: 'Audience', id: shared.id }]
      campaign = create(:campaign, account: account, inbox: sms_inbox, audience: audience)

      post preview, params: { audience: audience }, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['count']).to eq(campaign.audience_contacts.to_a.size)
    end

    it 'refuses personal and foreign audiences and a missing audience with 422' do
      [[{ type: 'Audience', id: personal.id }], [{ type: 'Audience', id: foreign.id }], []].each do |audience|
        post preview, params: { audience: audience }, headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it 'is for those who may create campaigns' do
      post preview, params: { audience: [{ type: 'Audience', id: shared.id }] }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      post preview, params: { audience: [{ type: 'Audience', id: shared.id }] }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'keeps campaigns for administrators only' do
    post "/api/v1/accounts/#{account.id}/campaigns",
         params: campaign_params.merge(audience: [{ type: 'Audience', id: shared.id }]),
         headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
