require 'rails_helper'

# Lynomia regression: two numbers on one WABA. Deleting one inbox must not unsubscribe the app from the WABA,
# so the other inbox keeps receiving webhooks. Only the last inbox of the WABA unsubscribes it.
RSpec.describe 'Deleting one of several WhatsApp inboxes on a shared WABA', type: :request do
  let(:account) { create(:account) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let(:app_secret) { 'lynomia-meta-app-secret' }
  let(:shared_waba_config) { { 'api_key' => 'token', 'business_account_id' => 'waba-shared', 'source' => 'embedded_signup' } }
  let(:channel_a) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+15550001001',
                              sync_templates: false, validate_provider_config: false)
      .tap { |channel| channel.update!(provider_config: shared_waba_config.merge('phone_number_id' => 'phone-a')) }
  end
  let(:channel_b) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+15550001002',
                              sync_templates: false, validate_provider_config: false)
      .tap { |channel| channel.update!(provider_config: shared_waba_config.merge('phone_number_id' => 'phone-b')) }
  end
  let(:inbound_to_b) do
    {
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          field: 'messages',
          value: {
            metadata: { display_phone_number: '15550001002', phone_number_id: 'phone-b' },
            contacts: [{ profile: { name: 'Customer' }, wa_id: '15557770001' }],
            messages: [{ from: '15557770001', id: 'wamid.after-sibling-delete', timestamp: Time.current.to_i.to_s,
                         type: 'text', text: { body: 'still here' } }]
          }
        }]
      }]
    }.to_json
  end

  before do
    InstallationConfig.where(name: 'WHATSAPP_APP_SECRET').delete_all
    GlobalConfig.clear_cache
    stub_request(:post, %r{graph\.facebook\.com/v[\d.]+/phone-[ab](/deregister)?\z})
      .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:delete, %r{graph\.facebook\.com/v[\d.]+/waba-shared/subscribed_apps})
      .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'keeps the WABA subscribed and the other inbox receiving webhooks' do
    inbox_a = channel_a.inbox
    inbox_b = channel_b.inbox

    perform_enqueued_jobs do
      delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox_a.id}", headers: administrator.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:success)
    expect(Inbox.exists?(inbox_a.id)).to be(false)
    expect(a_request(:delete, %r{/waba-shared/subscribed_apps})).not_to have_been_made

    with_modified_env WHATSAPP_APP_SECRET: app_secret do
      perform_enqueued_jobs do
        post "/webhooks/whatsapp/#{channel_b.phone_number}",
             params: inbound_to_b,
             headers: { 'CONTENT_TYPE' => 'application/json',
                        'X-Hub-Signature-256' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', app_secret, inbound_to_b)}" }
      end
    end

    expect(response).to have_http_status(:ok)
    expect(inbox_b.messages.find_by(source_id: 'wamid.after-sibling-delete')&.content).to eq('still here')
  end

  it 'unsubscribes the WABA when its last inbox is deleted' do
    inbox_a = channel_a.inbox

    perform_enqueued_jobs do
      delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox_a.id}", headers: administrator.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:success)
    expect(a_request(:delete, %r{/waba-shared/subscribed_apps})).to have_been_made.once
  end
end
