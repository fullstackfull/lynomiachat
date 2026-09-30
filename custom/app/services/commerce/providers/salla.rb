# Salla Merchant API (https://api.salla.dev/admin/v2) with the store's OAuth tokens from the Salla app installation
# (docs/commerce/11-salla-auth-and-token-lifecycle.md). Read-only: only GET requests exist here. The API host is fixed
# by Salla, never taken from a store or tenant setting, and every request carries a token from
# Commerce::Salla::TokenManager, never the credentials a caller passes in.
#
# Customers are found with Salla's keyword search (it matches mobile, email and name) and kept only when their E.164
# mobile or email matches exactly; names never match. Orders are one page of the customer's orders (customer_id filter),
# newest first; shipments come from the Shipments API per shown order.
#
# Rate limits are per store (docs/commerce/12-salla-security.md): when Salla answers 429 or reports no requests left,
# further calls for the merchant fail fast with RATE_LIMITED until Salla's reset time, so the panel serves its cache.
class Commerce::Providers::Salla < Commerce::Providers::Base
  API_BASE = URI('https://api.salla.dev/admin/v2').freeze
  SEARCH_LIMIT = 20
  # One page, the largest Salla allows, sorted here: the API's default order is not documented.
  ORDER_PAGE = 60

  def self.enabled? = Commerce::Salla::Config.enabled?

  # The token works and belongs to this store.
  def health
    raise Commerce::Error, 'AUTH_INVALID' unless store_identity[:external_store_id] == @store.external_store_id

    true
  end

  def store_identity
    @store_identity ||= Commerce::Salla::Oauth.user_info(token).slice(:external_store_id, :name)
  end

  def find_customers(email: nil, phone: nil)
    raise ArgumentError, 'pass exactly one of email or phone' unless [email, phone].compact.one?

    email = email.to_s.strip.downcase.presence
    term = email || Commerce::Phone.search_term(phone)
    return [] if term.blank?

    found = list('/customers', keyword: term, per_page: SEARCH_LIMIT).map { |raw| normalize_customer(raw) }
    found.select { |customer| email ? customer.emails.include?(email) : customer.phones.include?(phone) }
  end

  def list_customer_orders(external_customer_id, limit:)
    orders = list('/orders', customer_id: Integer(external_customer_id.to_s, 10), per_page: ORDER_PAGE).map { |raw| normalize_order(raw) }
    orders.sort_by { |order| order.created_at.to_s }.reverse.first(limit).map { |order| with_shipments(order) }
  end

  def get_order(external_order_id)
    raw = get("/orders/#{Integer(external_order_id.to_s, 10)}")['data']
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless raw.is_a?(Hash)

    with_shipments(normalize_order(raw))
  end

  def normalize_customer(raw)
    normalizer.customer(raw)
  end

  def normalize_order(raw)
    normalizer.order(raw)
  end

  private

  def with_shipments(order)
    shipments = list('/shipments', order_id: order.external_order_id).map { |raw| normalizer.shipment(raw) }
    normalizer.with_shipments(order, shipments)
  end

  def list(path, params = {})
    data = get(path, params)['data']
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless data.is_a?(Array) && data.all?(Hash)

    data
  end

  def get(path, params = {})
    Commerce::Backoff.check!(backoff_key)
    body = http.get_json(path, params)
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless body.is_a?(Hash)

    body
  ensure
    Commerce::Backoff.record(backoff_key, @http&.rate_limit)
  end

  def backoff_key = "COMMERCE::SALLA::MERCHANT::#{@store.external_store_id}::BACKOFF"

  def token
    @token ||= Commerce::Salla::TokenManager.new(@store).access_token
  end

  def http
    @http ||= Commerce::HttpClient.new(base_uri: API_BASE, authorization: "Bearer #{token}", log_tag: 'salla')
  end

  def normalizer
    @normalizer ||= Normalizer.new
  end
end
