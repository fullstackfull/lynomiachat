require 'rails_helper'

# Lynomia: WhatsApp credentials stay server-side. The dashboard gets provider_config without them, and a
# provider_config it sends back (calling settings, API key update, embedded -> manual transfer) keeps the stored ones.
RSpec.describe 'WhatsApp inbox credentials', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:access_token) { 'EAAG-secret-whatsapp-access-token' }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      .tap do |whatsapp_channel|
        whatsapp_channel.update!(provider_config: whatsapp_channel.provider_config.merge(
          'api_key' => access_token, 'verification_pin' => 482_913, 'app_secret' => 'customer-app-secret'
        ))
      end
  end
  let(:inbox) { channel.inbox }

  describe 'GET /api/v1/accounts/:account_id/inboxes/:id' do
    it 'returns provider_config to administrators without credentials' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      provider_config = response.parsed_body['provider_config']
      expect(provider_config.keys).to include('phone_number_id', 'business_account_id', 'source', 'webhook_verify_token')
      expect(provider_config.keys).not_to include(*Channel::Whatsapp::SECRET_PROVIDER_CONFIG_KEYS)
      expect(response.body).not_to include(access_token, 'customer-app-secret', '482913')
    end

    it 'does not return provider_config to agents' do
      create(:inbox_member, user: agent, inbox: inbox)
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).not_to have_key('provider_config')
      expect(response.body).not_to include(access_token)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/inboxes' do
    it 'never includes the access token in the list' do
      channel
      get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.body).to include('provider_config')
      expect(response.body).not_to include(access_token, 'customer-app-secret')
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/inboxes/:id' do
    before do
      stub_request(:get, %r{graph\.facebook\.com/v14\.0/\d+/message_templates})
        .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{graph\.facebook\.com/v14\.0/\d+/phone_numbers})
        .to_return(status: 200, body: { data: [{ id: '123456789' }, { id: '555000111' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'keeps the stored credentials when the dashboard sends back the provider_config it received' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: admin.create_new_auth_token, as: :json
      browser_config = response.parsed_body['provider_config']

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            headers: admin.create_new_auth_token,
            params: { channel: { provider_config: browser_config.merge('call_permission_request_body' => 'May we call you?') } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(channel.reload.provider_config).to include(
        'api_key' => access_token, 'verification_pin' => 482_913, 'app_secret' => 'customer-app-secret',
        'call_permission_request_body' => 'May we call you?'
      )
    end

    it 'replaces the access token when a new one is sent' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: admin.create_new_auth_token, as: :json
      browser_config = response.parsed_body['provider_config']

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            headers: admin.create_new_auth_token,
            params: { channel: { provider_config: browser_config.merge('api_key' => 'EAAG-rotated-token') } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(channel.reload.provider_config['api_key']).to eq('EAAG-rotated-token')
      expect(response.body).not_to include('EAAG-rotated-token')
    end

    it 'keeps the embedded signup to manual transfer working' do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: admin.create_new_auth_token, as: :json
      transfer_config = response.parsed_body['provider_config'].except('source')
                                .merge('phone_number_id' => '555000111', 'business_account_id' => '777000111', 'api_key' => 'EAAG-manual')

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
            headers: admin.create_new_auth_token,
            params: { channel: { provider_config: transfer_config } },
            as: :json

      expect(response).to have_http_status(:success)
      expect(channel.reload.provider_config).to include('api_key' => 'EAAG-manual', 'phone_number_id' => '555000111')
      expect(channel.provider_config).not_to have_key('source')
    end
  end
end
