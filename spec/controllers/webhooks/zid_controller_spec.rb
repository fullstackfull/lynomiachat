require 'rails_helper'

RSpec.describe 'Zid webhooks', type: :request do
  include_context 'with commerce encryption'
  include_context 'with zid app'
  include ActiveJob::TestHelper

  let(:store) do
    create(:commerce_store, :zid, external_store_id: '318001',
                                  credentials: { 'authorization' => 'auth-1', 'access_token' => 'manager-1', 'refresh_token' => 'refresh-1',
                                                 'expires_at' => 300.days.from_now.utc.iso8601,
                                                 'webhook_username' => 'a3f9c2d8e1b04f6a9c7d5e3b1a2f4c6d',
                                                 'webhook_password' => 'Zp7Hq2Vx9Lm4Rt8Kw3Ny6Bc1Df5Gj0Ts2Ua7Ie4Oo9Pz3Xr8Qv6Mb1Nc5Hd0Fe' })
  end
  let(:path) { "/webhooks/zid/#{store.external_store_id}" }
  let(:body) { JSON.parse(file_fixture('commerce/zid/orders.json').read)['orders'].first.to_json }

  let(:valid) { basic(store.credentials['webhook_username'], store.credentials['webhook_password']) }

  def basic(username, password)
    { 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(username, password), 'Content-Type' => 'application/json' }
  end

  it 'accepts a delivery with the store credentials and queues it encrypted' do
    post path, params: body, headers: valid

    expect(response).to have_http_status(:ok)
    job = enqueued_jobs.select { |enqueued| enqueued[:job] == Commerce::Zid::WebhookJob }.sole
    expect(job[:args].first).to eq(store.id)
    expect(job[:args].to_json).not_to include('Sara Ali', 'sara.ali@example.com', '966551112233')
  end

  it 'refuses a delivery without credentials, before reading the body' do
    post path, params: '{not json', headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:unauthorized)
    expect(Commerce::Zid::WebhookJob).not_to have_been_enqueued
  end

  it 'refuses a wrong username or a wrong password' do
    post path, params: body, headers: basic('someone-else', store.credentials['webhook_password'])
    expect(response).to have_http_status(:unauthorized)

    post path, params: body, headers: basic(store.credentials['webhook_username'], 'not-the-password')
    expect(response).to have_http_status(:unauthorized)

    post path, params: body, headers: { 'Authorization' => "Bearer #{store.credentials['webhook_password']}", 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
    expect(Commerce::Zid::WebhookJob).not_to have_been_enqueued
  end

  it "refuses another store's credentials and stores that are not connected" do
    other = create(:commerce_store, :zid, external_store_id: '318777',
                                          credentials: store.credentials.merge('webhook_username' => 'b' * 32, 'webhook_password' => 'c' * 64))

    post "/webhooks/zid/#{other.external_store_id}", params: body, headers: valid
    expect(response).to have_http_status(:unauthorized)

    store.update!(status: :disconnected)
    post path, params: body, headers: valid
    expect(response).to have_http_status(:unauthorized)

    post '/webhooks/zid/999999', params: body, headers: valid
    expect(response).to have_http_status(:unauthorized)
    expect(Commerce::Zid::WebhookJob).not_to have_been_enqueued
  end

  it 'refuses every delivery for a store whose webhooks were never registered' do
    store.update!(credentials: store.credentials.except('webhook_username', 'webhook_password'))

    post path, params: body, headers: basic('', '')

    expect(response).to have_http_status(:unauthorized)
  end

  it 'acknowledges a redelivered event without queueing it again' do
    2.times { post path, params: body, headers: valid }
    post path, params: JSON.parse(body).merge('payment_status' => 'refunded').to_json, headers: valid

    expect(response).to have_http_status(:ok)
    expect(Commerce::Zid::WebhookJob).to have_been_enqueued.twice
  end

  it 'never logs the password' do
    io = StringIO.new
    loggers = [Rails.logger, ActionController::Base.logger]
    Rails.logger = ActionController::Base.logger = ActiveSupport::Logger.new(io)
    begin
      post path, params: body, headers: valid
    ensure
      Rails.logger, ActionController::Base.logger = loggers
    end

    expect(io.string).to include('/webhooks/zid/318001')
    expect(io.string).not_to include(store.credentials['webhook_password'], Base64.strict_encode64("#{store.credentials['webhook_username']}:"))
  end
end
