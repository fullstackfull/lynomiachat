require 'rails_helper'

# Lynomia "WhatsApp Business" option: an existing WhatsApp Business App number connected through Meta Embedded
# Signup (Coexistence). Runs the real controller -> services -> channel path with only the Graph API stubbed.
RSpec.describe 'WhatsApp Business (Coexistence) onboarding', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }
  let(:graph) { "https://graph.facebook.com/#{Whatsapp::FacebookApiClient::DEFAULT_API_VERSION}" }
  let(:coexistence_params) { { code: 'coex-code', waba_id: 'waba-coex', is_coexistence: true } }
  let(:phone_numbers) do
    { data: [{ id: '3330001', display_phone_number: '+1 555-000-3001', verified_name: 'Lynomia Shop', code_verification_status: 'VERIFIED' }] }
  end

  before do
    create(:installation_config, name: 'WHATSAPP_APP_ID', value: 'meta-app-id')
    create(:installation_config, name: 'WHATSAPP_APP_SECRET', value: 'meta-app-secret')
    GlobalConfig.clear_cache

    stub_request(:get, "#{graph}/oauth/access_token")
      .with(query: { client_id: 'meta-app-id', client_secret: 'meta-app-secret', code: 'coex-code' })
      .to_return(status: 200, body: { access_token: 'coex-token' }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{graph\.facebook\.com/v[\d.]+/waba-coex/phone_numbers})
      .to_return(status: 200, body: phone_numbers.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{graph\.facebook\.com/v[\d.]+/waba-coex/message_templates})
      .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, "#{graph}/waba-coex/subscribed_apps")
      .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, "#{graph}/3330001")
      .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def authorize(user, account_id, params)
    post "/api/v1/accounts/#{account_id}/whatsapp/authorization", params: params, headers: user.create_new_auth_token, as: :json
  end

  it 'creates the same whatsapp_cloud inbox and marks it as Coexistence' do
    expect { authorize(administrator, account.id, coexistence_params) }
      .to change(Inbox, :count).by(1).and change(Channel::Whatsapp, :count).by(1)

    expect(response).to have_http_status(:success)
    channel = Inbox.find(response.parsed_body['id']).channel
    expect(channel.provider).to eq('whatsapp_cloud')
    expect(channel.inbox.name).to eq('+15550003001')
    expect(channel.provider_config).to include('source' => 'embedded_signup', 'is_coexistence' => true,
                                               'phone_number_id' => '3330001', 'business_account_id' => 'waba-coex')
    expect(channel.reauthorization_required?).to be(false)
  end

  it 'skips /register and the health probe but subscribes the webhooks once' do
    authorize(administrator, account.id, coexistence_params)

    expect(response).to have_http_status(:success)
    expect(a_request(:post, "#{graph}/3330001/register")).not_to have_been_made
    expect(a_request(:get, %r{/3330001\?})).not_to have_been_made
    expect(a_request(:post, "#{graph}/waba-coex/subscribed_apps")).to have_been_made.once
  end

  it 'does not create a second inbox, channel or webhook subscription for a repeated callback' do
    authorize(administrator, account.id, coexistence_params)

    expect { authorize(administrator, account.id, coexistence_params) }
      .not_to change(Channel::Whatsapp, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('+15550003001')
    expect(a_request(:post, "#{graph}/waba-coex/subscribed_apps")).to have_been_made.once
  end

  it 'rejects the same number from another tenant' do
    authorize(administrator, account.id, coexistence_params)

    expect { authorize(other_administrator, other_account.id, coexistence_params) }
      .not_to change(Channel::Whatsapp, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'logs one sanitized completion line without the code, token or app secret' do
    log = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log))

    authorize(administrator, account.id, coexistence_params)

    expect(response).to have_http_status(:success)
    expect(log.string).to include("[WHATSAPP SIGNUP COMPLETION] account_id=#{account.id} flow=create is_coexistence=true " \
                                  'waba_id=waba-coex business_id_present=false phone_number_id=absent code_present=true result=success')
    expect(log.string).not_to include('coex-code', 'coex-token', 'meta-app-secret')
  end

  it 'logs the failure class of a completion without the code or app secret' do
    stub_request(:get, "#{graph}/oauth/access_token").with(query: hash_including(code: 'coex-code'))
                                                     .to_return(status: 400, body: { error: { message: 'Code expired' } }.to_json)
    log = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log))

    authorize(administrator, account.id, coexistence_params)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(log.string).to include('[WHATSAPP SIGNUP COMPLETION]').and include('result=RuntimeError')
    expect(log.string).not_to include('coex-code', 'meta-app-secret')
  end

  it 'does not let an agent create a WhatsApp Business inbox' do
    expect { authorize(agent, account.id, coexistence_params) }.not_to change(Inbox, :count)

    expect(response).to have_http_status(:unauthorized)
    expect(a_request(:get, "#{graph}/oauth/access_token")).not_to have_been_made
  end

  it 'does not let an unauthenticated request create a WhatsApp Business inbox' do
    post "/api/v1/accounts/#{account.id}/whatsapp/authorization", params: coexistence_params, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(a_request(:get, "#{graph}/oauth/access_token")).not_to have_been_made
  end

  context 'with an existing Coexistence inbox' do
    let!(:inbox) do
      authorize(administrator, account.id, coexistence_params)
      Inbox.find(response.parsed_body['id'])
    end

    it 'does not let another tenant reauthorize it' do
      authorize(other_administrator, other_account.id, coexistence_params.merge(inbox_id: inbox.id))

      expect(response).to have_http_status(:not_found)
    end

    it 'does not let another tenant act inside this account' do
      authorize(other_administrator, account.id, coexistence_params)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not let an agent reauthorize it' do
      authorize(agent, account.id, coexistence_params.merge(inbox_id: inbox.id))

      expect(response).to have_http_status(:unauthorized)
    end

    it 'never returns the token to agents' do
      create(:inbox_member, user: agent, inbox: inbox)
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).not_to have_key('provider_config')
      expect(response.body).not_to include('coex-token')
    end
  end

  it 'creates nothing when the authorization code has expired' do
    stub_request(:get, "#{graph}/oauth/access_token")
      .with(query: hash_including(code: 'expired-code'))
      .to_return(status: 400, body: { error: { message: 'Error validating verification code', code: 100 } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    expect { authorize(administrator, account.id, coexistence_params.merge(code: 'expired-code')) }
      .not_to change(Channel::Whatsapp, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
