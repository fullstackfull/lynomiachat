# The Zid webhook subscriptions of one store (docs/commerce/15-zid-webhook-security.md). They only tell Lynomia that a
# customer's orders changed, so their cached orders are read again: Lynomia keeps no order database.
#
# Every subscription of the Lynomia app in a store shares the app's original_id, so registering first deletes them all
# (DELETE /managers/webhooks?original_id=…) and subscribes each event again: re-authorizing never duplicates them, and
# every registration gets a new, random Basic Auth pair for Zid to send with each delivery. The pair is saved, encrypted
# with the store's credentials, before Zid can use it; subscription ids are kept in the store's metadata.
class Commerce::Zid::Webhooks
  EVENTS = %w[order.create order.status.update order.payment_status.update].freeze
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
        ids = EVENTS.filter_map { |event| client.post_json(PATH, subscription(event, auth)).then { |body| body['id'].to_s if body.is_a?(Hash) } }
        @store.update!(metadata: @store.metadata.merge('zid_webhooks' => { 'ids' => ids, 'registered_at' => Time.current.iso8601 }))
      end
    end
  end

  # Before a disconnect: Zid stops sending this store's events to Lynomia.
  def unregister
    tokens.with_credentials { |credentials| remove(Commerce::Zid::Oauth.api(credentials)) }
  end

  private

  def remove(client)
    client.delete(PATH, original_id: Commerce::Zid::Config.client_id)
  rescue Commerce::Error => e
    raise unless e.code == 'NOT_FOUND'
  end

  # VERIFY(zid-webhook-auth): Zid made Basic Authentication mandatory for webhooks on 2026-09-30 (Zid Partner changelog
  # 57336, "Webhook Security Changes"), with the credentials set when the webhook is created. The request field that
  # carries them could not be read from Zid's documentation from Lynomia's build environment, so it is set here only;
  # a delivery without these credentials is refused whatever Zid did with them.
  def subscription(event, auth)
    { event: event, target_url: target_url, original_id: Commerce::Zid::Config.client_id,
      authentication: { type: 'basic', username: auth['webhook_username'], password: auth['webhook_password'] } }
  end

  def target_url = "#{ENV.fetch('FRONTEND_URL')}/webhooks/zid/#{@store.external_store_id}"

  def tokens = Commerce::Zid::TokenManager.new(@store)
end
