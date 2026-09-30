# WooCommerce REST API v3 with a merchant-created Read key (HTTP Basic over TLS). Read-only: only GET requests exist here.
#
# Customer identity: a registered customer is its WooCommerce customer id; a guest checkout has no id, so it is
# "guest:<email>" or "guest:<E.164 phone>", the verified identifier it was found by. Candidates are discovered with
# WooCommerce's broad search and kept only when a billing/shipping email or phone matches exactly.
class Commerce::Providers::Woocommerce < Commerce::Providers::Base
  API_PATH = '/wp-json/wc/v3'.freeze
  GUEST_PREFIX = 'guest:'.freeze
  SEARCH_LIMIT = 20

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

  # Works with both order storages: WooCommerce redirects this HPOS screen to post.php when HPOS is off.
  def admin_order_url(external_order_id)
    id = Integer(external_order_id.to_s, 10)
    raise ArgumentError, 'order id must be positive' unless id.positive?

    "#{@store.base_url}/wp-admin/admin.php?#{{ page: 'wc-orders', action: 'edit', id: id }.to_query}"
  end

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
    @http ||= Commerce::HttpClient.new(base_uri: base_uri, username: @credentials.fetch('consumer_key'),
                                       password: @credentials.fetch('consumer_secret'), log_tag: 'woocommerce')
  end

  def base_uri
    @base_uri ||= Commerce::StoreUrl.parse(@store.base_url)
  end

  def normalizer
    @normalizer ||= Normalizer.new(self)
  end
end
