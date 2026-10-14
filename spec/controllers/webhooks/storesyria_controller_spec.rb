require 'rails_helper'

# P3D, receiving side. Store Syria's commerce outbox delivers here.
#
# The properties worth pinning are the ones that decide whether a delivery can be forged or
# replayed, and whether a store's events can be made to land on another store -- not that the
# happy path returns 200.
RSpec.describe 'Store Syria commerce event deliveries', type: :request do
  include_context 'with commerce encryption'
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:token) { "lsc_4_1_#{'a' * 64}" }
  let(:store) do
    create(:commerce_store, account: account, provider: 'storesyria', name: 'Damascus',
                            base_url: 'https://storesyria.test', external_store_id: 'storesyria.test:4',
                            credentials: { 'commerce_token' => token })
  end
  let(:body) do
    { event: 'order.status_changed', external_store_id: 'storesyria.test:4', order_id: '55',
      customer_reference: '4', delivered_status: 6, payment_status: 'paid',
      occurred_at: '2026-01-01T12:00:00Z', delivery_id: 'd1f6c0b0-0000-4000-8000-000000000001' }.to_json
  end
  let(:timestamp) { Time.now.to_i.to_s }

  # The same derivation Store Syria performs: a key derived from the commerce credential under
  # its own purpose label, never the credential itself.
  def sign(raw, at, secret = token)
    key = OpenSSL::HMAC.hexdigest('SHA256', secret, 'storesyria-commerce-events')
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', key, "#{at}.#{raw}")}"
  end

  def deliver(raw: body, at: timestamp, signature: nil, external: 'storesyria.test:4', delivery: SecureRandom.uuid)
    post '/webhooks/storesyria', params: raw,
                                 headers: { 'CONTENT_TYPE' => 'application/json', 'X-Storesyria-Store' => external,
                                            'X-Storesyria-Timestamp' => at, 'X-Storesyria-Delivery' => delivery,
                                            'X-Storesyria-Signature' => signature || sign(raw, at) }
  end

  before do
    account.enable_features!('lynomia_commerce')
    store
  end

  it 'accepts a signed delivery and queues it once' do
    expect { deliver }.to have_enqueued_job(Commerce::Storesyria::WebhookJob)
    expect(response).to have_http_status(:ok)
  end

  # Nothing in the body is read before the signature checks out, so a forged delivery cannot
  # reach the queue at all -- not merely fail later.
  it 'refuses a forged signature without queueing anything' do
    expect { deliver(signature: sign(body, timestamp, 'lsc_4_1_wrong')) }.not_to have_enqueued_job

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses a delivery with no signature at all' do
    post '/webhooks/storesyria', params: body,
                                 headers: { 'CONTENT_TYPE' => 'application/json', 'X-Storesyria-Store' => 'storesyria.test:4' }

    expect(response).to have_http_status(:unauthorized)
  end

  # THE SIGNATURE COVERS THE TIMESTAMP, so a captured delivery cannot be re-presented with a
  # fresh one; the window bounds how long the original stays usable at all.
  it 'refuses a delivery whose timestamp is outside the window, and a timestamp swapped for a fresh one' do
    old = 10.minutes.ago.to_i.to_s
    deliver(at: old, signature: sign(body, old))
    expect(response).to have_http_status(:unauthorized)

    deliver(at: Time.now.to_i.to_s, signature: sign(body, old))
    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses a body that was altered after signing' do
    deliver(raw: body.sub('"delivered_status":6', '"delivered_status":1'), signature: sign(body, timestamp))

    expect(response).to have_http_status(:unauthorized)
  end

  # ONE STORE'S EVENTS CANNOT BE MADE TO LAND ON ANOTHER. The header names the store, and the
  # signature is what proves the name: re-pointing it at a second store makes the key wrong.
  it 'refuses a delivery addressed to a different store' do
    other = create(:commerce_store, account: account, provider: 'storesyria', base_url: 'https://other.test',
                                    external_store_id: 'storesyria.test:9', credentials: { 'commerce_token' => "lsc_9_1_#{'b' * 64}" })

    deliver(external: other.external_store_id)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses a delivery naming a store this installation does not have' do
    deliver(external: 'somewhere.else:1')

    expect(response).to have_http_status(:unauthorized)
  end

  # A credential revoked in Store Syria changes the key, so deliveries stop verifying the
  # instant reads do -- one act, both directions.
  it 'refuses deliveries signed with a credential this store no longer holds' do
    store.update!(credentials: { 'commerce_token' => "lsc_4_2_#{'c' * 64}" })

    deliver

    expect(response).to have_http_status(:unauthorized)
  end

  it 'queues a redelivery of the same event only once' do
    id = SecureRandom.uuid
    deliver(delivery: id)

    expect { deliver(delivery: id) }.not_to have_enqueued_job
    expect(response).to have_http_status(:ok)
  end

  describe 'applying the event' do
    let(:contact) { create(:contact, account: account) }

    def cached(identifier) = Commerce::Cache.fetch(store, :orders, identifier) { [] }

    # The cache key hashes its identifier, so it is built the way Commerce::Cache builds it
    # rather than spelled out here, where it would silently stop matching.
    def outdated?(identifier)
      key = Commerce::Cache.send(:key, store, :orders, identifier)
      JSON.parse(Redis::Alfred.get(key).to_s)['outdated'] == true
    end

    before do
      create(:commerce_customer_link, store: store, contact: contact, external_customer_id: '4')
      Commerce::Cache.purge(store)
    end

    it 'marks the named customer\'s cached orders outdated so the next read goes to the store' do
      cached('4')
      expect(outdated?('4')).to be(false)

      perform_enqueued_jobs(only: Commerce::Storesyria::WebhookJob) { deliver }

      expect(outdated?('4')).to be(true)
    end

    # An order with no customer at all names none, and the whole store's cache goes rather than
    # a guess being made about whose orders changed.
    it 'invalidates the whole store when the event names no customer' do
      cached('9')
      payload = JSON.parse(body).merge('customer_reference' => nil).to_json

      perform_enqueued_jobs(only: Commerce::Storesyria::WebhookJob) { deliver(raw: payload, signature: sign(payload, timestamp)) }

      expect(outdated?('9')).to be(true)
    end
  end
end
