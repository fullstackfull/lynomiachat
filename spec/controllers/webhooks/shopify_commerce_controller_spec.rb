require 'rails_helper'

RSpec.describe 'Shopify Commerce webhooks', type: :request do
  include_context 'with commerce encryption'
  include_context 'with shopify commerce app'
  include ActiveJob::TestHelper

  let(:body) do
    { id: 6_001_006, email: 'sara.ali@example.com', customer: { id: 7001, email: 'sara.ali@example.com', phone: '+966551112233' } }.to_json
  end
  let(:sign) { ->(payload, secret = shopify_client_secret) { Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, payload)) } }
  let(:headers) do
    { 'Content-Type' => 'application/json', 'X-Shopify-Topic' => 'orders/updated', 'X-Shopify-Shop-Domain' => 'lynomia-demo.myshopify.com',
      'X-Shopify-Webhook-Id' => 'b54557e4-bdd9-4b37-8a5f-bf7d70bcd043', 'X-Shopify-Triggered-At' => '2026-09-30T10:00:00.123456789Z',
      'X-Shopify-API-Version' => '2026-07', 'X-Shopify-Hmac-Sha256' => sign.call(body) }
  end
  let(:queued) { enqueued_jobs.select { |job| job[:job] == Commerce::Shopify::WebhookJob } }

  it 'queues a delivery signed with the app secret, with its body encrypted' do
    post '/webhooks/shopify_commerce', params: body, headers: headers

    expect(response).to have_http_status(:ok)
    arguments = queued.sole[:args]
    expect(arguments.first(3)).to eq(['orders/updated', 'lynomia-demo.myshopify.com', '2026-09-30T10:00:00.123456789Z'])
    expect(arguments.to_json).not_to include('sara.ali@example.com', '+966551112233')
    expect(Commerce::WebhookQueue.unseal('shopify', arguments.last)).to eq(JSON.parse(body))
  end

  it 'refuses a missing, wrong or wrong-key signature, and a body changed after signing, before reading it' do
    [
      headers.except('X-Shopify-Hmac-Sha256'),
      headers.merge('X-Shopify-Hmac-Sha256' => ''),
      headers.merge('X-Shopify-Hmac-Sha256' => sign.call(body).reverse),
      headers.merge('X-Shopify-Hmac-Sha256' => sign.call(body, 'legacy-shopify-app-secret')),
      headers.merge('X-Shopify-Hmac-Sha256' => OpenSSL::HMAC.hexdigest('SHA256', shopify_client_secret, body))
    ].each do |forged|
      post '/webhooks/shopify_commerce', params: body, headers: forged

      expect(response).to have_http_status(:unauthorized)
    end
    post '/webhooks/shopify_commerce', params: body.sub('7001', '7002'), headers: headers
    expect(response).to have_http_status(:unauthorized)
    post '/webhooks/shopify_commerce', params: '{not json', headers: headers
    expect(response).to have_http_status(:unauthorized)

    expect(queued).to be_empty
  end

  it 'queues a delivery once: a retry with the same webhook id is acknowledged without being queued again' do
    2.times { post '/webhooks/shopify_commerce', params: body, headers: headers }
    post '/webhooks/shopify_commerce', params: body, headers: headers.merge('X-Shopify-Webhook-Id' => 'a-new-delivery')

    expect(response).to have_http_status(:ok)
    expect(queued.size).to eq(2)
    key = "COMMERCE::SHOPIFY::WEBHOOK::#{Digest::SHA256.hexdigest('b54557e4-bdd9-4b37-8a5f-bf7d70bcd043')}"
    expect(Redis::Alfred.ttl(key)).to be_between(1, 1.day.to_i)
  end

  it 'refuses a signed delivery without a webhook id or with a shop that is not a myshopify.com domain' do
    post '/webhooks/shopify_commerce', params: body, headers: headers.except('X-Shopify-Webhook-Id')
    expect(response).to have_http_status(:bad_request)

    post '/webhooks/shopify_commerce', params: body, headers: headers.merge('X-Shopify-Shop-Domain' => 'evil.example.com')
    expect(response).to have_http_status(:bad_request)
    expect(queued).to be_empty
  end

  it 'accepts the privacy topics and the uninstall while Shopify Commerce is switched off, and ignores unknown topics' do
    InstallationConfig.find_by!(name: 'SHOPIFY_COMMERCE_ENABLED').update!(value: false)
    GlobalConfig.clear_cache

    %w[customers/data_request customers/redact shop/redact app/uninstalled products/update].each_with_index do |topic, index|
      post '/webhooks/shopify_commerce', params: body, headers: headers.merge('X-Shopify-Topic' => topic, 'X-Shopify-Webhook-Id' => "id-#{index}")

      expect(response).to have_http_status(:ok)
    end
    expect(queued.map { |job| job[:args].first }).to eq(%w[customers/data_request customers/redact shop/redact app/uninstalled])
  end

  it 'stays apart from the legacy Shopify integration: neither endpoint accepts the other app signature' do
    InstallationConfig.where(name: 'SHOPIFY_CLIENT_SECRET').first_or_initialize.update!(value: 'legacy-shopify-app-secret', locked: false)
    GlobalConfig.clear_cache

    post '/webhooks/shopify', params: body, headers: headers.merge('X-Shopify-Topic' => 'shop/redact')
    expect(response).to have_http_status(:unauthorized)

    post '/webhooks/shopify_commerce', params: body, headers: headers.merge('X-Shopify-Hmac-Sha256' => sign.call(body, 'legacy-shopify-app-secret'))
    expect(response).to have_http_status(:unauthorized)
    expect(queued).to be_empty
  end
end
