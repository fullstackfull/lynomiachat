require 'rails_helper'

# WooCommerce webhook deliveries (docs/commerce/26-realtime-security.md): WooCommerce's signature with the store's own
# secret, checked before the body is read; once per delivery; never the order data in a job argument.
RSpec.describe 'WooCommerce webhooks', type: :request do
  include_context 'with commerce encryption'
  include ActiveJob::TestHelper

  let(:secret) { SecureRandom.hex(32) }
  let(:store) { create(:commerce_store, credentials: { 'consumer_key' => 'ck_1', 'consumer_secret' => 'cs_1', 'webhook_secret' => secret }) }
  let(:other_store) do
    create(:commerce_store, credentials: { 'consumer_key' => 'ck_2', 'consumer_secret' => 'cs_2', 'webhook_secret' => SecureRandom.hex(32) })
  end
  let(:path) { "/webhooks/woocommerce/#{store.id}" }
  let(:body) { JSON.parse(file_fixture('commerce/woocommerce/orders.json').read).first.to_json }
  let(:queued) { -> { enqueued_jobs.select { |job| job[:job] == Commerce::Woocommerce::WebhookJob } } }

  def headers(signed_body, signing_secret: secret, topic: 'order.updated', delivery: SecureRandom.hex(20))
    { 'Content-Type' => 'application/json', 'X-WC-Webhook-Topic' => topic, 'X-WC-Webhook-Delivery-ID' => delivery,
      'X-WC-Webhook-Signature' => Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', signing_secret, signed_body)) }
  end

  before { Redis::Alfred.scan_each(match: 'COMMERCE::WOOCOMMERCE::WEBHOOK::*') { |key| Redis::Alfred.delete(key) } }

  it 'accepts a delivery signed with the store secret and queues it encrypted' do
    post path, params: body, headers: headers(body)

    expect(response).to have_http_status(:ok)
    job = queued.call.sole
    expect(job[:args].first).to eq(store.id)
    expect(job[:args].to_json).not_to include('billing', '@', JSON.parse(body)['billing']['phone'].to_s.presence || 'no-phone')
  end

  it 'refuses unsigned, wrongly signed, tampered and hex-signed deliveries, before reading the body' do
    hex = headers(body).merge('X-WC-Webhook-Signature' => OpenSSL::HMAC.hexdigest('SHA256', secret, body))
    [
      [body, headers(body).except('X-WC-Webhook-Signature')],
      [body, headers(body, signing_secret: 'not-the-secret')],
      ["#{body} ", headers(body)],
      [body, hex],
      ['{not json', headers('{not json', signing_secret: 'x')]
    ].each do |sent_body, sent_headers|
      post path, params: sent_body, headers: sent_headers
      expect(response).to have_http_status(:unauthorized)
    end
    expect(queued.call).to be_empty
  end

  it 'refuses WooCommerce\'s unsigned creation ping' do
    post path, params: 'webhook_id=12', headers: { 'Content-Type' => 'application/x-www-form-urlencoded' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses a delivery signed for another store, a disconnected store, a store without a webhook secret and an unknown store' do
    post path, params: body, headers: headers(body, signing_secret: other_store.credentials['webhook_secret'])
    expect(response).to have_http_status(:unauthorized)

    read_only = create(:commerce_store)
    post "/webhooks/woocommerce/#{read_only.id}", params: body, headers: headers(body, signing_secret: '')
    expect(response).to have_http_status(:unauthorized)

    post '/webhooks/woocommerce/999999999', params: body, headers: headers(body)
    expect(response).to have_http_status(:unauthorized)

    store.update!(status: :disconnected)
    post path, params: body, headers: headers(body)
    expect(response).to have_http_status(:unauthorized)
    expect(queued.call).to be_empty
  end

  it 'queues a delivery once, and acknowledges its replay' do
    sent = headers(body, delivery: 'delivery-1')
    2.times { post path, params: body, headers: sent }

    expect(response).to have_http_status(:ok)
    expect(queued.call.size).to eq(1)
    expect(Redis::Alfred.ttl("COMMERCE::WOOCOMMERCE::WEBHOOK::#{store.id}::#{Digest::SHA256.hexdigest('delivery-1')}")).to be_between(1, 1.day)
  end

  it 'refreshes the contact linked to the order\'s customer, through the realtime core' do
    order = JSON.parse(body)
    contact = create(:contact, account: store.account)
    customer_id = order['customer_id'].to_i.positive? ? order['customer_id'].to_s : "guest:#{order['billing']['email'].downcase}"
    link = Commerce::CustomerLink.create!(account: store.account, store: store, contact: contact, match_source: :manual,
                                          external_customer_id: customer_id)

    perform_enqueued_jobs(only: Commerce::Woocommerce::WebhookJob) { post path, params: body, headers: headers(body) }

    expect(enqueued_jobs.select { |job| job[:job] == Commerce::RefreshJob }.map { |job| job[:args] }).to eq([[link.id]])
  end

  it 'acknowledges and drops topics Lynomia did not subscribe to' do
    post path, params: body, headers: headers(body, topic: 'product.updated')

    expect(response).to have_http_status(:ok)
    expect(queued.call).to be_empty
  end
end
