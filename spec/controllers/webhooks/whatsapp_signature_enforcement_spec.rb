require 'rails_helper'

# Lynomia: every WhatsApp Cloud webhook must carry a valid X-Hub-Signature-256, manual numbers included.
RSpec.describe 'Webhooks::WhatsappController signature enforcement', type: :request do
  let(:app_secret) { 'lynomia-meta-app-secret' }
  let(:global_app_secret) { app_secret }
  let(:provider_config) { { 'api_key' => 'test_key', 'phone_number_id' => '105550001' } }
  # The factory forces an Embedded Signup config, so the exact provider_config under test is written after create.
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).tap do |whatsapp_channel|
      whatsapp_channel.update!(provider_config: provider_config)
    end
  end
  let(:path) { "/webhooks/whatsapp/#{channel.phone_number}" }
  let(:body) do
    {
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          field: 'messages',
          value: {
            metadata: { display_phone_number: channel.phone_number.delete_prefix('+'), phone_number_id: '105550001' },
            messages: [{ id: 'wamid.signature', from: '15550001111', type: 'text', text: { body: 'hello' } }]
          }
        }]
      }]
    }.to_json
  end
  let(:signature) { "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', app_secret, body)}" }
  let(:headers) { { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature } }

  before do
    InstallationConfig.where(name: 'WHATSAPP_APP_SECRET').delete_all
    GlobalConfig.clear_cache
    allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
  end

  shared_examples 'a Meta-signed WhatsApp webhook' do
    it 'accepts a payload signed with the app secret' do
      with_modified_env(WHATSAPP_APP_SECRET: global_app_secret) { post path, params: body, headers: headers }

      expect(response).to have_http_status(:ok)
      expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later)
    end

    it 'rejects a payload without a signature' do
      with_modified_env(WHATSAPP_APP_SECRET: global_app_secret) do
        post path, params: body, headers: headers.except('X-Hub-Signature-256')
      end

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    end

    it 'rejects an invalid signature' do
      with_modified_env(WHATSAPP_APP_SECRET: global_app_secret) do
        post path, params: body, headers: headers.merge('X-Hub-Signature-256' => "sha256=#{'0' * 64}")
      end

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    end

    it 'rejects a body modified after signing' do
      with_modified_env(WHATSAPP_APP_SECRET: global_app_secret) do
        post path, params: body.sub('hello', 'tampered'), headers: headers
      end

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    end

    it 'rejects a payload signed with another secret' do
      forged = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'attacker-secret', body)}"
      with_modified_env(WHATSAPP_APP_SECRET: global_app_secret) do
        post path, params: body, headers: headers.merge('X-Hub-Signature-256' => forged)
      end

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    end

    it 'keeps the GET verification challenge working' do
      get path, params: { 'hub.mode' => 'subscribe', 'hub.challenge' => '4242',
                          'hub.verify_token' => channel.provider_config['webhook_verify_token'] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('4242')
    end
  end

  context 'with a manual Cloud API number set up before manual_setup_v2 (no source)' do
    it_behaves_like 'a Meta-signed WhatsApp webhook'

    it 'rejects a correctly signed payload when no app secret is configured on the server' do
      with_modified_env(WHATSAPP_APP_SECRET: nil) { post path, params: body, headers: headers }

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    end

    it 'logs the rejection without the app secret or the signature' do
      allow(Rails.logger).to receive(:warn)
      with_modified_env(WHATSAPP_APP_SECRET: global_app_secret) do
        post path, params: body, headers: headers.merge('X-Hub-Signature-256' => "sha256=#{'a' * 64}")
      end

      expect(Rails.logger).to have_received(:warn).with("Rejected Meta webhook with invalid X-Hub-Signature-256: #{path}")
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including(app_secret))
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including('a' * 64))
    end
  end

  context 'with a manual_setup_v2 Cloud API number' do
    let(:provider_config) { { 'api_key' => 'test_key', 'phone_number_id' => '105550001', 'source' => 'manual_setup_v2' } }

    it_behaves_like 'a Meta-signed WhatsApp webhook'
  end

  context 'with a manual Cloud API number connected through its own Meta app' do
    let(:global_app_secret) { 'another-meta-app-secret' }
    let(:provider_config) { { 'api_key' => 'test_key', 'phone_number_id' => '105550001', 'app_secret' => app_secret } }

    it_behaves_like 'a Meta-signed WhatsApp webhook'
  end

  context 'with an Embedded Signup number' do
    let(:provider_config) do
      { 'api_key' => 'test_key', 'phone_number_id' => '105550001', 'business_account_id' => '205550001', 'source' => 'embedded_signup' }
    end

    it_behaves_like 'a Meta-signed WhatsApp webhook'
  end

  context 'with a WhatsApp Business (Coexistence) number' do
    let(:provider_config) do
      { 'api_key' => 'test_key', 'phone_number_id' => '105550001', 'business_account_id' => '205550001',
        'source' => 'embedded_signup', 'is_coexistence' => true }
    end

    it_behaves_like 'a Meta-signed WhatsApp webhook'
  end
end
