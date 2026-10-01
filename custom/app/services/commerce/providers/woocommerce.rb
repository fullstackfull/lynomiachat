# WooCommerce REST API v3 with a merchant-created key (HTTP Basic over TLS). Reads need a Read key. With a Read/Write key
# Lynomia also creates its webhooks (realtime) and, once the store's administrator opts in, performs order actions
# (Commerce::Providers::Woocommerce::Actions).
#
# Customer identity: a registered customer is its WooCommerce customer id; a guest checkout has no id, so it is
# "guest:<email>" or "guest:<E.164 phone>", the verified identifier it was found by. Candidates are discovered with
# WooCommerce's broad search and kept only when a billing/shipping email or phone matches exactly.
class Commerce::Providers::Woocommerce < Commerce::Providers::Base
  API_PATH = '/wp-json/wc/v3'.freeze
  GUEST_PREFIX = 'guest:'.freeze
  SEARCH_LIMIT = 20
  WEBHOOK_TOPICS = %w[order.created order.updated order.deleted].freeze
  WEBHOOK_NAME = 'Lynomia Commerce'.freeze
  REALTIME_WRITE_ACCESS = { 'active' => 'granted', 'read_only_key' => 'read_only_key' }.freeze

  def self.supports_realtime? = true

  def self.registers_webhooks? = true

  def self.supports_actions? = true

  # Write access is proven by the webhook registration (it creates webhooks with the key) and revoked by a write the store
  # refuses: write_access is granted or read_only_key. Stores registered before it was recorded fall back to their
  # realtime status.
  def write_access_problem
    access = @store.metadata['write_access'] || REALTIME_WRITE_ACCESS[@store.metadata.dig('realtime', 'status')]
    { 'granted' => nil, 'read_only_key' => 'read_only_key' }.fetch(access, 'write_access_unverified')
  end

  def action_snapshot(external_order_id) = actions.snapshot(external_order_id)

  def perform_action(action_type, snapshot, params, idempotency_key) = actions.perform(action_type, snapshot, params, idempotency_key)

  def reconcile_action(run, snapshot) = actions.reconcile(run, snapshot)

  def health
    index = get('', _fields: 'namespace')
    raise Commerce::Error.new('STORE_UNAVAILABLE', reason: 'woocommerce_api_not_found') unless index.is_a?(Hash) && index['namespace'] == 'wc/v3'

    list('/orders', per_page: 1, _fields: 'id')
    list('/customers', per_page: 1, role: 'all', _fields: 'id')
    true
  rescue Commerce::Error => e
    raise Commerce::Error.new('STORE_UNAVAILABLE', reason: 'woocommerce_api_not_found') if e.code == 'NOT_FOUND'

    raise
  end

  def store_identity
    { external_store_id: Commerce::StoreUrl.external_id(base_uri), name: base_uri.host }
  end

  def find_customers(email: nil, phone: nil)
    raise ArgumentError, 'pass exactly one of email or phone' unless [email, phone].compact.one?

    identifier = email ? email.to_s.strip.downcase : phone
    registered = email ? list('/customers', email: identifier, role: 'all').map { |raw| normalize_customer(raw) } : []
    from_orders = search_orders(identifier).map { |raw| normalizer.customer_from_order(raw, "#{GUEST_PREFIX}#{identifier}") }
    merge(registered.select { |customer| customer.emails.include?(identifier) } + from_orders)
  end

  def list_customer_orders(external_customer_id, limit:)
    key = external_customer_id.to_s
    orders = if key.start_with?(GUEST_PREFIX)
               search_orders(key.delete_prefix(GUEST_PREFIX), customer: 0)
             else
               list('/orders', customer: Integer(key, 10), per_page: limit, orderby: 'date', order: 'desc')
             end
    orders.first(limit).map { |raw| normalize_order(raw) }
  end

  def get_order(external_order_id)
    raw = get("/orders/#{Integer(external_order_id.to_s, 10)}")
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless raw.is_a?(Hash)

    normalize_order(raw)
  end

  # WooCommerce numbers orders by their id unless a plugin renumbers them (such a store's orders are not found by number).
  def self.searches_orders? = true

  # Works with both order storages: WooCommerce redirects this HPOS screen to post.php when HPOS is off.
  def admin_order_url(external_order_id)
    id = Integer(external_order_id.to_s, 10)
    raise ArgumentError, 'order id must be positive' unless id.positive?

    "#{@store.base_url}/wp-admin/admin.php?#{{ page: 'wc-orders', action: 'edit', id: id }.to_query}"
  end

  # Subscribes the store's order events to Lynomia (docs/commerce/24-realtime-architecture.md §4): Lynomia's previous
  # webhooks in the store are deleted, a new random secret is saved (encrypted, before WooCommerce can use it) and one
  # webhook per topic is created with it. WooCommerce accepts webhook changes only from a key with write permission: with a
  # Read key nothing is created, no secret is kept, and the store works as before, refreshed by the cache and on request.
  def register_webhooks
    Commerce::StoreLock.with('woocommerce_webhooks', @store.id) do
      existing = list('/webhooks', per_page: 100, _fields: 'id,delivery_url').select { |hook| hook['delivery_url'] == delivery_url }
      begin
        existing.each { |hook| http.delete("#{API_PATH}/webhooks/#{Integer(hook['id'].to_s, 10)}", force: true) }
        ids = create_webhooks
        realtime!('active', ids)
      rescue Commerce::Error => e
        raise unless e.code == 'AUTH_INVALID'

        @store.update!(credentials: @store.reload.credentials.except('webhook_secret'))
        realtime!('read_only_key', [])
      end
    end
  end

  # Before a disconnect: the webhooks Lynomia created are deleted (a Read key cannot, and WooCommerce then disables them
  # after five refused deliveries).
  def release
    Array(@store.metadata.dig('realtime', 'webhook_ids')).each do |id|
      http.delete("#{API_PATH}/webhooks/#{Integer(id.to_s, 10)}", force: true)
    rescue Commerce::Error => e
      raise unless e.code == 'NOT_FOUND'
    end
  end

  # The customer an order event is about: its customer id, or for a guest checkout every guest identity the order
  # carries (normalized billing email and phones), as guest links keep them.
  def event_customer_ids(payload)
    return [] unless payload.is_a?(Hash) && payload.key?('customer_id')

    customer_id = Integer(payload['customer_id'].to_s, 10)
    customer_id.positive? ? [customer_id.to_s] : normalizer.order_identifiers(payload).map { |identifier| "#{GUEST_PREFIX}#{identifier}" }
  rescue ArgumentError, TypeError, NoMethodError
    []
  end

  def event_order_id(payload) = payload.is_a?(Hash) ? payload['id']&.to_s : nil

  def normalize_customer(raw)
    normalizer.customer(raw)
  end

  def normalize_order(raw)
    normalizer.order(raw)
  end

  private

  # Orders whose billing/shipping email or phone equals `identifier` exactly; the WooCommerce search is a substring
  # match over many fields, so it only narrows the candidates.
  def search_orders(identifier, **filters)
    term = identifier.include?('@') ? identifier : Commerce::Phone.search_term(identifier)
    return [] if term.blank?

    list('/orders', search: term, per_page: SEARCH_LIMIT, orderby: 'date', order: 'desc', **filters)
      .select { |raw| normalizer.order_identifiers(raw).include?(identifier) }
  end

  def create_webhooks
    secret = SecureRandom.hex(32)
    @store.update!(credentials: @store.reload.credentials.merge('webhook_secret' => secret))
    WEBHOOK_TOPICS.map do |topic|
      hook = http.post_json("#{API_PATH}/webhooks", name: WEBHOOK_NAME, topic: topic, delivery_url: delivery_url, secret: secret, status: 'active')
      raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless hook.is_a?(Hash) && hook['id']

      hook['id'].to_s
    end
  end

  def realtime!(status, webhook_ids)
    @store.update!(metadata: @store.metadata.merge('realtime' => { 'status' => status, 'webhook_ids' => webhook_ids,
                                                                   'registered_at' => Time.current.iso8601 },
                                                   'write_access' => status == 'active' ? 'granted' : 'read_only_key'))
  end

  def delivery_url = "#{ENV.fetch('FRONTEND_URL')}/webhooks/woocommerce/#{@store.id}"

  def merge(customers)
    customers.group_by(&:external_id).map do |external_id, group|
      Commerce::Customer.new(external_id: external_id, name: group.filter_map(&:name).first, emails: group.flat_map(&:emails).uniq,
                             phones: group.flat_map(&:phones).uniq, registered: group.first.registered)
    end
  end

  def list(path, params = {})
    result = get(path, params)
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless result.is_a?(Array) && result.all?(Hash)

    result
  end

  def get(path, params = {})
    http.get_json("#{API_PATH}#{path}", params)
  end

  def http
    @http ||= begin
      basic = Base64.strict_encode64("#{@credentials.fetch('consumer_key')}:#{@credentials.fetch('consumer_secret')}")
      Commerce::HttpClient.new(base_uri: base_uri, authorization: "Basic #{basic}", log_tag: 'woocommerce')
    end
  end

  def base_uri
    @base_uri ||= Commerce::StoreUrl.parse(@store.base_url)
  end

  def normalizer
    @normalizer ||= Normalizer.new(self)
  end

  def actions
    @actions ||= Actions.new(self, http, @store)
  end
end
