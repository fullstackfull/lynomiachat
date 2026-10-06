# The Zid webhook subscriptions of one store (docs/commerce/15-zid-webhook-security.md). They only tell Lynomia that a
# customer's orders changed, so their cached orders are read again: Lynomia keeps no order database.
#
# Every subscription of the Lynomia app in a store shares the app's original_id, so registering first deletes them all
# (DELETE /managers/webhooks?original_id=…) and subscribes each event again: re-authorizing never duplicates them, and
# every registration gets a new, random Basic Auth pair for Zid to send with each delivery. The pair is saved, encrypted
# with the store's credentials, before Zid can use it; subscription ids are kept in the store's metadata.
class Commerce::Zid::Webhooks
  # Zid's officially documented events, and only those. The two abandoned-cart events give Lynomia a
  # provider-authoritative cart lifecycle (docs/commerce-production/06-cart-transition-design.md); there is no
  # cart.updated event, so a cart's changes between abandonment and completion are not observable by push.
  EVENTS = (%w[order.create order.status.update order.payment_status.update] +
            Commerce::Providers::Zid::CartEvents::EVENTS).freeze
  PATH = '/managers/webhooks'.freeze

  def initialize(store)
    @store = store
  end

  def register
    Commerce::StoreLock.with('zid_webhooks', @store.external_store_id) do
      tokens.with_credentials do |credentials|
        client = Commerce::Zid::Oauth.api(credentials)
        remove(client)
        auth = { 'webhook_username' => SecureRandom.hex(16), 'webhook_password' => SecureRandom.urlsafe_base64(48) }
        @store.update!(credentials: @store.reload.credentials.merge(auth))
        ids = EVENTS.map { |event| subscribe(client, event, auth) }
        @store.update!(metadata: @store.metadata.merge('zid_webhooks' => { 'ids' => ids, 'registered_at' => Time.current.iso8601 }))
      end
    end
  end

  # Before a disconnect: Zid stops sending this store's events to Lynomia.
  def unregister
    tokens.with_credentials { |credentials| remove(Commerce::Zid::Oauth.api(credentials)) }
  end

  private

  # One subscription, and a failure is a failure. This used to be a `filter_map` that dropped any response without an
  # id, so a store where two of the three POSTs failed was recorded as registered with one id and `register` returned
  # normally — the same shape of untruthful success as the webhook-setup defect in docs/real-whatsapp-uat/09-fix.md.
  # Raising leaves the caller to decide, and the store's metadata is only written once every event is subscribed.
  def subscribe(client, event, auth)
    body = client.post_json(PATH, subscription(event, auth))
    id = body['id'].to_s.presence if body.is_a?(Hash)
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'zid_webhook_subscribe') if id.nil?

    id
  end

  def remove(client)
    client.delete(PATH, original_id: Commerce::Zid::Config.client_id)
  rescue Commerce::Error => e
    raise unless e.code == 'NOT_FOUND'
  end

  # Zid's documented create-webhook body takes `username` and `password` at the TOP LEVEL, alongside `event`,
  # `target_url` and `original_id`: "If `username` and `password` are provided when creating a webhook, Zid will
  # include a `Basic Authentication` header when sending webhook requests" (docs.zid.sa/create-a-webhook, read
  # 2026-10-06). Basic Auth is the only mechanism Zid offers — there is no HMAC and no signing secret — and it
  # became mandatory for every webhook on 2026-09-30 (Partner changelog 57336).
  #
  # This previously sent a nested `authentication: { type:, username:, password: }` object, which Zid does not
  # define. The consequence was not a visible error: Zid would accept the subscription, ignore the unknown key and
  # register the webhook with NO credentials, then deliver with no Authorization header — and
  # Webhooks::ZidController refuses a credential-less delivery with 401. Every order event would have been lost
  # silently, and Zid's circuit breaker treats non-2xx as failure: 30 in an hour marks the webhook BROKEN and it
  # stops dispatching altogether (docs.zid.sa/webhook-health-tracking).
  def subscription(event, auth)
    { event: event, target_url: target_url, original_id: Commerce::Zid::Config.client_id,
      username: auth['webhook_username'], password: auth['webhook_password'] }
  end

  def target_url = "#{ENV.fetch('FRONTEND_URL')}/webhooks/zid/#{@store.external_store_id}"

  def tokens = Commerce::Zid::TokenManager.new(@store)
end
