require 'rails_helper'

# Realtime security across the four providers (docs/commerce/26-realtime-security.md): store webhooks reach the realtime
# core only when authentic, once per delivery, for their own store and account; what they trigger never carries customer
# data and never reaches another account.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Commerce realtime security', type: :request do
  include_context 'with four commerce stores'

  let(:woo_secret) { SecureRandom.hex(32) }
  let(:zid_basic) { ['u' * 32, 'p' * 64] }
  let(:deliveries) do
    woo_body = woo_orders[24].to_json
    salla_body = { event: 'order.updated', merchant: 1_234_509_876, data: { id: 1_861_092_002, customer: { id: 1_227_534_533 } } }.to_json
    zid_body = { id: 41_000_102, customer: { id: 90_001 } }.to_json
    shopify_body = { id: 6_001_006, customer: { id: 7001 } }.to_json
    {
      woocommerce: ["/webhooks/woocommerce/#{woo.id}", woo_body, woo_headers(woo_body, woo_secret)],
      salla: ['/webhooks/salla', salla_body, salla_headers(salla_body, salla_webhook_secret)],
      zid: ["/webhooks/zid/#{zid.external_store_id}", zid_body, zid_headers(*zid_basic)],
      shopify: ['/webhooks/shopify_commerce', shopify_body, shopify_headers(shopify_body, shopify_client_secret)]
    }
  end
  let(:forged) do
    {
      woocommerce: woo_headers(deliveries[:woocommerce][1], 'not-the-secret'),
      salla: salla_headers(deliveries[:salla][1], 'not-the-secret'),
      zid: zid_headers(zid_basic.first, 'not-the-password'),
      shopify: shopify_headers(deliveries[:shopify][1], 'not-the-secret')
    }
  end
  let(:outdated) do
    -> { [woo, salla, zid, shopify].flat_map { |store| cache_keys.call(store) }.select { |key| JSON.parse(Redis::Alfred.get(key))['outdated'] } }
  end
  let(:broadcasts) do
    -> { enqueued_jobs.select { |job| job[:job] == ActionCableBroadcastJob && job[:args][1] == 'commerce.customer.updated' } }
  end

  def woo_headers(body, secret, delivery: 'woo-delivery-1')
    { 'Content-Type' => 'application/json', 'X-WC-Webhook-Topic' => 'order.updated', 'X-WC-Webhook-Delivery-ID' => delivery,
      'X-WC-Webhook-Signature' => Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, body)) }
  end

  def salla_headers(body, secret)
    { 'Content-Type' => 'application/json', 'X-Salla-Security-Strategy' => 'Signature',
      'X-Salla-Signature' => OpenSSL::HMAC.hexdigest('SHA256', secret, body) }
  end

  def zid_headers(username, password)
    { 'Content-Type' => 'application/json', 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }
  end

  def shopify_headers(body, secret)
    { 'Content-Type' => 'application/json', 'X-Shopify-Topic' => 'orders/updated', 'X-Shopify-Shop-Domain' => 'lynomia-demo.myshopify.com',
      'X-Shopify-Webhook-Id' => 'shopify-delivery-1',
      'X-Shopify-Hmac-Sha256' => Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, body)) }
  end

  def deliver(provider, headers = nil)
    path, body, authentic = deliveries.fetch(provider)
    post path, params: body, headers: headers || authentic
    response.status
  end

  def webhook_jobs = [Commerce::Woocommerce::WebhookJob, Commerce::Salla::WebhookJob, Commerce::Zid::WebhookJob, Commerce::Shopify::WebhookJob]

  before do
    woo.update!(credentials: woo.credentials.merge('webhook_secret' => woo_secret))
    zid.update!(credentials: zid.credentials.merge('webhook_username' => zid_basic.first, 'webhook_password' => zid_basic.last))
    %w[WOOCOMMERCE SALLA ZID SHOPIFY].each do |provider|
      Redis::Alfred.scan_each(match: "COMMERCE::#{provider}::WEBHOOK::*") { |key| Redis::Alfred.delete(key) }
    end
    Redis::Alfred.scan_each(match: "COMMERCE::REFRESH::ACCOUNT::#{account.id}::*") { |key| Redis::Alfred.delete(key) }
    [woo, salla, zid, shopify].each { |store| panel.call(store) }
    clear_enqueued_jobs
  end

  it 'refuses a forged delivery for every provider, and nothing is outdated, refreshed or broadcast' do
    allow(Commerce::Metrics).to receive(:event).and_call_original
    expect(forged.keys.map { |provider| deliver(provider, forged[provider]) }).to eq([401, 401, 401, 401])
    %w[woocommerce salla zid shopify].each do |provider|
      expect(Commerce::Metrics).to have_received(:event).with('commerce.webhook.rejected', hash_including(provider: provider))
    end
    perform_enqueued_jobs

    expect(enqueued_jobs).to be_empty
    expect(performed_jobs).to be_empty
    expect(outdated.call).to be_empty
  end

  it 'acts once on an authentic delivery replayed, and tells only this account, with ids only' do
    allow(Commerce::Metrics).to receive(:event).and_call_original
    expect(deliveries.keys.map { |provider| deliver(provider) }).to eq([200, 200, 200, 200])
    expect(deliveries.keys.map { |provider| deliver(provider) }).to eq([200, 200, 200, 200])
    %w[woocommerce salla zid shopify].product(%w[accepted duplicate]).each do |provider, kind|
      expect(Commerce::Metrics).to have_received(:event).with("commerce.webhook.#{kind}", hash_including(provider: provider)).once
    end
    expect(enqueued_jobs.count { |job| webhook_jobs.include?(job[:job]) }).to eq(4)

    perform_enqueued_jobs(only: webhook_jobs)
    refreshes = enqueued_jobs.select { |job| job[:job] == Commerce::RefreshJob }
    expect(refreshes.map { |job| job[:args].first }).to match_array(Commerce::CustomerLink.where(contact: contact).ids)
    perform_enqueued_jobs(only: Commerce::RefreshJob)

    expect(broadcasts.call.size).to eq(4)
    broadcasts.call.each do |job|
      tokens, _event, data = job[:args]
      expect(tokens).to eq(["account_#{account.id}"])
      expect(data.except('_aj_symbol_keys').keys).to contain_exactly('account_id', 'contact_id', 'store_id', 'updated_at')
      expect(data).to include('account_id' => account.id, 'contact_id' => contact.id)
    end
    expect(broadcasts.call.to_json).not_to include('551112233', 'Omar', '@', 'total', 'token')
    expect(outdated.call).to be_empty
  end

  it 'refuses a delivery authenticated for one store on another store, in this account or another' do
    credentials = ->(key) { { 'consumer_key' => "ck_#{key}", 'consumer_secret' => "cs_#{key}", 'webhook_secret' => SecureRandom.hex(32) } }
    other_woo = create(:commerce_store, account: account, base_url: 'https://two.example.com', external_store_id: 'two.example.com',
                                        credentials: credentials.call(2))
    foreign_woo = create(:commerce_store, base_url: 'https://three.example.com', external_store_id: 'three.example.com',
                                          credentials: credentials.call(3))
    foreign_zid = create(:commerce_store, :zid, external_store_id: '318002',
                                                credentials: zid.credentials.merge('webhook_username' => 'x' * 32, 'webhook_password' => 'y' * 64))
    _path, woo_body, woo_signed = deliveries[:woocommerce]
    _path, zid_body, zid_signed = deliveries[:zid]

    [other_woo, foreign_woo].each do |store|
      post "/webhooks/woocommerce/#{store.id}", params: woo_body, headers: woo_signed
      expect(response).to have_http_status(:unauthorized)
    end
    post "/webhooks/zid/#{foreign_zid.external_store_id}", params: zid_body, headers: zid_signed
    expect(response).to have_http_status(:unauthorized)
    expect(enqueued_jobs.select { |job| webhook_jobs.include?(job[:job]) }).to be_empty
  end

  it 'never refreshes or tells another account that links a customer with the same store id' do
    other_account = create(:account)
    other_zid = create(:commerce_store, :zid, account: other_account, external_store_id: '318009')
    other_link = create(:commerce_customer_link, store: other_zid, account: other_account, contact: create(:contact, account: other_account),
                                                 external_customer_id: '90001')

    deliver(:zid)
    perform_enqueued_jobs(only: webhook_jobs)
    expect(enqueued_jobs.select { |job| job[:job] == Commerce::RefreshJob }.map { |job| job[:args].first })
      .to eq([zid.customer_links.sole.id])
    perform_enqueued_jobs(only: Commerce::RefreshJob)

    expect(broadcasts.call.map { |job| job[:args].first }).to eq([["account_#{account.id}"]])
    expect(broadcasts.call.to_json).not_to include(other_link.contact_id.to_s.then { |id| "\"contact_id\":#{id}" })
  end

  it 'treats a malformed customer identity as naming nobody: the store\'s orders are outdated, nobody is refreshed' do
    body = { id: 41_000_102, customer: { id: '90001 OR 1=1' } }.to_json
    post "/webhooks/zid/#{zid.external_store_id}", params: body, headers: zid_headers(*zid_basic)
    perform_enqueued_jobs(only: webhook_jobs)

    expect(enqueued_jobs.select { |job| job[:job] == Commerce::RefreshJob }).to be_empty
    expect(outdated.call.size).to eq(cache_keys.call(zid).count { |key| key.include?('::ORDERS::') })
  end

  it 'shows nothing stale once a refresh finds the store\'s credentials rejected' do
    deliver(:zid)
    perform_enqueued_jobs(only: webhook_jobs)
    zid_customer_orders.to_return(status: 401, body: '{"status":401,"success":false}')
    stub_request(:post, 'https://oauth.zid.sa/oauth/token').to_return(status: 400, body: '{"error":"invalid_grant"}')
    perform_enqueued_jobs(only: Commerce::RefreshJob)

    expect(zid.reload).to be_needs_reauth
    expect(cache_keys.call(zid)).to be_empty
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/commerce/overview", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['stores'].find { |entry| entry['store']['id'] == zid.id })
      .to include('state' => 'needs_reauth', 'orders_count' => nil)
    expect(response.parsed_body['latest_orders'].map { |order| order['store']['id'] }).not_to include(zid.id)
  end
end
# rubocop:enable RSpec/MultipleExpectations
