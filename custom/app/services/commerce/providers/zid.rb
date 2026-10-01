# Zid Merchant API (https://api.zid.sa/v1) with the store's OAuth tokens from the Zid app authorization
# (docs/commerce/16-zid-provider.md). Read-only: only GET requests exist here. The API host is fixed by Zid, never taken
# from a store or tenant setting, and every request carries the tokens from Commerce::Zid::TokenManager, never the
# credentials a caller passes in.
#
# Customers are found through the orders list's documented search (search_term matches the customer's phone, email,
# name or the order code) and kept only when their E.164 mobile or email matches exactly; names never match, and
# marketplace or masked customers never match. A linked customer's orders are one page of the customer_id filter, newest
# first, and each is re-checked to belong to that customer. Orders are requested with payload_type=default, the payload
# that includes products and the marketplace flag.
#
# Zid allows 60 requests a minute per app and store: when it answers 429 or reports no requests left, further calls for
# the store fail fast with RATE_LIMITED (Commerce::Backoff), so the panel serves its cache.
class Commerce::Providers::Zid < Commerce::Providers::Base
  SEARCH_LIMIT = 20
  ORDER_PAGE = 50

  def self.enabled? = Commerce::Zid::Config.enabled?

  # The tokens work and belong to this store.
  def health
    raise Commerce::Error, 'AUTH_INVALID' unless store_identity[:external_store_id] == @store.external_store_id

    true
  end

  def store_identity
    @store_identity ||= tokens.with_credentials { |credentials| Commerce::Zid::Oauth.profile(credentials) }.slice(:external_store_id, :name)
  end

  def find_customers(email: nil, phone: nil)
    raise ArgumentError, 'pass exactly one of email or phone' unless [email, phone].compact.one?

    email = email.to_s.strip.downcase.presence
    term = email || Commerce::Phone.search_term(phone)
    return [] if term.blank?

    exact(orders(search_term: term, per_page: SEARCH_LIMIT).filter_map { |raw| normalizer.order_candidate(raw) }, email, phone)
  end

  def list_customer_orders(external_customer_id, limit:)
    id = Integer(external_customer_id.to_s, 10)
    own = orders(customer_id: id, per_page: ORDER_PAGE, sort_by: 'desc').select { |raw| raw['customer'].is_a?(Hash) && raw['customer']['id'] == id }
    own.map { |raw| normalize_order(raw) }.sort_by { |order| order.created_at.to_s }.reverse.first(limit)
  end

  def get_order(external_order_id)
    raw = get("/managers/store/orders/#{Integer(external_order_id.to_s, 10)}/view")['order']
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless raw.is_a?(Hash)

    normalize_order(raw)
  end

  # The number the panel shows is Zid's order id (docs/commerce/16-zid-provider.md).
  def self.searches_orders? = true

  def self.supports_realtime? = true

  # Zid's order events (order.create, order.status.update, order.payment_status.update) carry the order at the top level,
  # with its customer (docs/commerce/15-zid-webhook-security.md §8 for what is still to confirm on a live store).
  def event_customer_ids(payload)
    customer = payload['customer'] if payload.is_a?(Hash)
    id = Integer(customer['id'].to_s, 10) if customer.is_a?(Hash)
    id&.positive? ? [id.to_s] : []
  rescue ArgumentError, TypeError
    []
  end

  def event_order_id(payload) = payload.is_a?(Hash) ? payload['id']&.to_s : nil

  # Zid stops sending the store's order events to Lynomia.
  def release
    Commerce::Zid::Webhooks.new(@store).unregister
  end

  def normalize_customer(raw)
    normalizer.customer(raw)
  end

  def normalize_order(raw)
    normalizer.order(raw)
  end

  private

  # The search only discovers candidates: a customer is kept when its email or E.164 phone matches exactly.
  def exact(customers, email, phone)
    customers.select { |customer| email ? customer.emails.include?(email) : customer.phones.include?(phone) }.uniq(&:external_id)
  end

  def orders(params)
    list = get('/managers/store/orders', params.merge(payload_type: 'default'))['orders']
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless list.is_a?(Array) && list.all?(Hash)

    list
  end

  def get(path, params = {})
    Commerce::Backoff.check!(backoff_key)
    tokens.with_credentials { |credentials| request(credentials, path, params) }
  end

  def request(credentials, path, params)
    client = Commerce::Zid::Oauth.api(credentials)
    body = client.get_json(path, params)
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless body.is_a?(Hash)

    body
  rescue Commerce::Error => e
    # Zid answers some rejected tokens with a redirect to its login page instead of a 401.
    raise e.reason == 'redirect' ? Commerce::Error.new('AUTH_INVALID', reason: 'zid_login_redirect') : e
  ensure
    Commerce::Backoff.record(backoff_key, client&.rate_limit)
  end

  def backoff_key = "COMMERCE::ZID::MERCHANT::#{@store.external_store_id}::BACKOFF"

  def tokens
    @tokens ||= Commerce::Zid::TokenManager.new(@store)
  end

  def normalizer
    @normalizer ||= Normalizer.new(time_zone: @store.metadata['time_zone'])
  end
end
