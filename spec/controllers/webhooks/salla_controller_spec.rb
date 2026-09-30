require 'rails_helper'

RSpec.describe 'Salla app webhooks', type: :request do
  include ActiveJob::TestHelper
  include_context 'with commerce encryption'
  include_context 'with salla app'

  let(:body) { file_fixture('commerce/salla/app_store_authorize.json').read }
  let(:signature) { OpenSSL::HMAC.hexdigest('SHA256', salla_webhook_secret, body) }
  let(:headers) { { 'CONTENT_TYPE' => 'application/json', 'X-Salla-Security-Strategy' => 'Signature', 'X-Salla-Signature' => signature } }

  def deliver(payload = body, extra = {})
    post '/webhooks/salla', params: payload, headers: headers.merge(extra)
  end

  it 'accepts a delivery signed with the webhook secret and queues it encrypted' do
    expect { deliver }.to have_enqueued_job(Commerce::Salla::WebhookJob)

    expect(response).to have_http_status(:ok)
    expect(enqueued_jobs.to_json).not_to include('salla-access-token-fixture', 'salla-refresh-token-fixture', '1234509876')
  end

  {
    'no signature' => { 'X-Salla-Signature' => nil },
    'an invalid signature' => { 'X-Salla-Signature' => 'a' * 64 },
    'a signature made with another secret' => { 'X-Salla-Signature' => OpenSSL::HMAC.hexdigest('SHA256', 'another-secret', 'x') },
    'another security strategy' => { 'X-Salla-Security-Strategy' => 'Token' },
    'no security strategy' => { 'X-Salla-Security-Strategy' => nil }
  }.each do |label, changed|
    it "refuses a delivery with #{label}" do
      expect { deliver(body, changed.merge('X-Salla-Signature' => changed.fetch('X-Salla-Signature', signature))) }
        .not_to have_enqueued_job

      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'refuses a body that was changed after signing' do
    expect { deliver(body.sub('1234509876', '1234509877')) }.not_to have_enqueued_job

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses the signature of another secret for this body' do
    expect { deliver(body, 'X-Salla-Signature' => OpenSSL::HMAC.hexdigest('SHA256', 'wrong-secret', body)) }.not_to have_enqueued_job

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses everything while no webhook secret is configured' do
    InstallationConfig.find_by!(name: 'SALLA_WEBHOOK_SECRET').update!(value: '')
    GlobalConfig.clear_cache

    expect { deliver(body, 'X-Salla-Signature' => OpenSSL::HMAC.hexdigest('SHA256', '', body)) }.not_to have_enqueued_job
    expect(response).to have_http_status(:unauthorized)
  end

  it 'processes a redelivery of the same event once' do
    expect { 3.times { deliver } }.to have_enqueued_job(Commerce::Salla::WebhookJob).exactly(:once)

    expect(response).to have_http_status(:ok)
  end

  it 'keeps tokens and connection codes out of the request log' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    settings = JSON.parse(file_fixture('commerce/salla/app_settings_updated.json').read)

    logged = filter.filter(JSON.parse(body).merge('settings_event' => settings)).to_json

    expect(logged).not_to include('salla-access-token-fixture', 'salla-refresh-token-fixture', 'ABCD-EFGH-JKLM-NPQR')
  end

  describe 'processing' do
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }

    before do
      stub_request(:get, 'https://accounts.salla.sa/oauth2/user/info').to_return(status: 200,
                                                                                 body: file_fixture('commerce/salla/user_info.json').read)
    end

    it 'connects a store from signed events end to end' do
      code = Commerce::Salla::ConnectionCode.create(account: account, user: admin)[:code]
      settings = JSON.parse(file_fixture('commerce/salla/app_settings_updated.json').read)
      settings['data']['settings']['lynomia_connection_code'] = code
      settings_body = settings.to_json

      perform_enqueued_jobs do
        deliver(settings_body, 'X-Salla-Signature' => OpenSSL::HMAC.hexdigest('SHA256', salla_webhook_secret, settings_body))
        deliver
      end

      expect(account.commerce_stores.sole).to have_attributes(provider: 'salla', external_store_id: '1234509876', status: 'active')
    end

    it 'reports an event that cannot succeed instead of retrying it' do
      payload = JSON.parse(body).deep_merge('data' => { 'scope' => 'offline_access orders.read_write' }).to_json
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original

      perform_enqueued_jobs do
        deliver(payload, 'X-Salla-Signature' => OpenSSL::HMAC.hexdigest('SHA256', salla_webhook_secret, payload))
      end

      expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(Commerce::Error))
      expect(Commerce::Store.count).to eq(0)
    end

    it 'retries when Salla is unreachable' do
      stub_request(:get, 'https://accounts.salla.sa/oauth2/user/info').to_raise(Errno::ECONNREFUSED)

      expect { Commerce::Salla::WebhookJob.perform_now(sealed_job_argument) }.to raise_error(Commerce::Error)
    end

    def sealed_job_argument
      deliver
      enqueued_jobs.last[:args].first
    end
  end
end
