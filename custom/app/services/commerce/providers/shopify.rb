# Shopify Admin GraphQL API (pinned to Commerce::Shopify::Config::API_VERSION) with the store's expiring offline token
# from the Lynomia Commerce Shopify app (docs/commerce/19-shopify-graphql-provider.md). Queries, plus the two order
# action mutations of Commerce::Providers::Shopify::Actions (orderCancel, refundCreate) when the token holds write_orders.
# The API host is the store's validated myshopify.com domain, and every request carries the token from
# Commerce::Shopify::TokenManager, never the credentials a caller passes in. Values travel as GraphQL variables;
# search strings come from Commerce::Shopify::SearchQuery.
#
# Customers: the `customers` search by exact (quoted) email or phone, kept only when the customer's default email or
# E.164 phone matches exactly; names are never read or matched. Guests: a guest checkout has no Shopify customer, so it
# is "guest:<email>" (no Shopify customer id is invented), found through the orders email filter and kept only when the
# order has no customer and its email matches exactly. The orders API has no phone filter, so guests are found by email
# only. Orders: a customer's last ORDER_PAGE by creation, newest first, re-checked to belong to that customer (or guest).
# Without read_all_orders, Shopify returns the last 60 days of orders.
#
# Shopify's query cost budget: a THROTTLED answer, or a budget too low for another query like the last one, stops
# further calls for the store until the budget recovers (Commerce::Backoff), so the panel serves its cache.
class Commerce::Providers::Shopify < Commerce::Providers::Base
  GUEST_PREFIX = 'guest:'.freeze
  SEARCH_LIMIT = 20
  # Bounds of one order: its first line items (item_count is the order's full quantity), fulfillments and tracking numbers.
  ITEM_LIMIT = 10
  FULFILLMENT_LIMIT = 10
  TRACKING_LIMIT = 5
  CUSTOMERS_QUERY = <<~GRAPHQL.freeze
    query LynomiaCustomers($first: Int!, $query: String!) {
      customers(first: $first, query: $query) {
        nodes { id defaultEmailAddress { emailAddress } defaultPhoneNumber { phoneNumber } }
      }
    }
  GRAPHQL
  GUEST_ORDERS_QUERY = <<~GRAPHQL.freeze
    query LynomiaGuestOrders($first: Int!, $query: String!) {
      orders(first: $first, query: $query, sortKey: CREATED_AT, reverse: true) {
        nodes { id email customer { id } }
      }
    }
  GRAPHQL
  ORDER_FIELDS = <<~GRAPHQL.freeze
    id legacyResourceId name createdAt updatedAt cancelledAt email
    displayFinancialStatus displayFulfillmentStatus subtotalLineItemsQuantity
    currentTotalPriceSet { presentmentMoney { amount currencyCode } }
    customer { id }
    lineItems(first: #{ITEM_LIMIT}) { nodes { name quantity discountedTotalSet { presentmentMoney { amount } } } }
    fulfillments(first: #{FULFILLMENT_LIMIT}) {
      status displayStatus trackingInfo(first: #{TRACKING_LIMIT}) { company number url }
    }
  GRAPHQL
  ORDERS_QUERY = <<~GRAPHQL.freeze
    query LynomiaOrders($first: Int!, $query: String!) {
      orders(first: $first, query: $query, sortKey: CREATED_AT, reverse: true) { nodes { #{ORDER_FIELDS} } }
    }
  GRAPHQL
  ORDER_QUERY = <<~GRAPHQL.freeze
    query LynomiaOrder($id: ID!) { order(id: $id) { #{ORDER_FIELDS} } }
  GRAPHQL
  ACTION_ORDER_QUERY = <<~GRAPHQL.freeze
    query LynomiaOrderActions($id: ID!) { order(id: $id) { #{ORDER_FIELDS} #{Commerce::Providers::Shopify::Actions::FIELDS} } }
  GRAPHQL

  def self.enabled? = Commerce::Shopify::Config.enabled?

  # The token works and belongs to this shop.
  def health
    raise Commerce::Error, 'AUTH_INVALID' unless store_identity[:external_store_id] == @store.external_store_id

    true
  end

  def store_identity
    @store_identity ||= tokens.with_credentials { |credentials| Commerce::Shopify::Oauth.identity(shop, credentials['access_token']) }
  end

  def find_customers(email: nil, phone: nil)
    raise ArgumentError, 'pass exactly one of email or phone' unless [email, phone].compact.one?
    return customers(Commerce::Shopify::SearchQuery.phone(phone)).select { |customer| customer.phones.include?(phone) } if phone

    email = email.to_s.strip.downcase
    return [] if email.blank?

    (customers(Commerce::Shopify::SearchQuery.email(email)).select { |customer| customer.emails.include?(email) } + guests(email)).uniq(&:external_id)
  end

  def list_customer_orders(external_customer_id, limit:)
    key = external_customer_id.to_s
    if key.start_with?(GUEST_PREFIX)
      email = key.delete_prefix(GUEST_PREFIX)
      own = orders(Commerce::Shopify::SearchQuery.email(email), SEARCH_LIMIT).select { |raw| normalizer.guest_order?(raw, email) }
    else
      gid = "gid://shopify/Customer/#{Integer(key, 10)}"
      own = orders(Commerce::Shopify::SearchQuery.customer_id(key), limit).select { |raw| raw.dig('customer', 'id') == gid }
    end
    own.first(limit).map { |raw| normalize_order(raw) }
  end

  def get_order(external_order_id)
    raw = query(ORDER_QUERY, id: "gid://shopify/Order/#{Integer(external_order_id.to_s, 10)}")['order']
    raise Commerce::Error, 'NOT_FOUND' if raw.nil?

    normalize_order(raw)
  end

  def self.searches_orders? = true

  # Orders whose name is the number (the panel shows the name without its "#"), re-checked exactly.
  def find_orders(number)
    orders(Commerce::Shopify::SearchQuery.order_name(number), SEARCH_LIMIT).map { |raw| normalize_order(raw) }
                                                                           .select { |order| order.order_number == number }
  end

  def self.supports_realtime? = true

  def self.supports_actions? = true

  def self.supports_carts? = true

  def cart_access_problem = nil

  def abandoned_carts(customer_reference: nil, limit: 20) = carts.recent(limit) # rubocop:disable Lint/UnusedMethodArgument

  def abandoned_cart(external_cart_id) = carts.find(external_cart_id)

  def recovery_hosts = [shop, carts.primary_domain].compact

  # write_orders is granted only by an administrator's reconnect for order actions; a write Shopify refuses as
  # ACCESS_DENIED also marks it missing until the next authorization.
  def write_access_problem
    granted = @store.credentials.to_h['scope'].to_s.split(',').map(&:strip)
    granted.include?('write_orders') && @store.metadata['write_access'] != 'missing_scope' ? nil : 'missing_scope'
  end

  def action_snapshot(external_order_id)
    actions.snapshot(action_order(external_order_id))
  end

  def perform_action(action_type, snapshot, params, idempotency_key)
    case action_type
    when 'cancel_order' then actions.cancel(snapshot, params, idempotency_key)
    when 'refund_full', 'refund_partial' then actions.refund(snapshot, params, idempotency_key)
    else raise ArgumentError, "unsupported action #{action_type}"
    end
  end

  def reconcile_action(run, snapshot)
    actions.reconcile(run, snapshot, action_order(run.external_resource_id))
  end

  # One mutation, sent once: [HTTP status, parsed body] (Commerce::Shopify::Graphql#mutate).
  def mutate(document, variables)
    Commerce::Backoff.check!(backoff_key)
    tokens.with_credentials { |credentials| Commerce::Shopify::Graphql.new(shop, credentials['access_token']).mutate(document, variables) }
  end

  # One query for the action and cart readers (Commerce::Providers::Shopify::Actions, ::Carts).
  def read(document, variables = {}) = query(document, variables)

  # An orders/create or orders/updated body: its customer's id, or for a guest checkout the order's email as guest links
  # keep it. Tracking-only changes that do not update the order arrive with no event (docs/commerce/20 §1).
  def event_customer_ids(payload)
    return [] unless payload.is_a?(Hash)

    customer_id = payload.dig('customer', 'id') if payload['customer'].is_a?(Hash)
    return [Integer(customer_id.to_s, 10).to_s] if customer_id

    email = payload['email'].to_s.strip.downcase
    email.present? ? ["#{GUEST_PREFIX}#{email}"] : []
  rescue ArgumentError, TypeError
    []
  end

  def event_order_id(payload) = payload.is_a?(Hash) ? payload['id']&.to_s : nil

  # Built from the store's validated myshopify.com domain and the order's numeric id, never from a URL in a response.
  def admin_order_url(external_order_id)
    id = Integer(external_order_id.to_s, 10)
    raise ArgumentError, 'order id must be positive' unless id.positive?

    "https://#{shop}/admin/orders/#{id}"
  end

  def normalize_customer(raw)
    normalizer.customer(raw)
  end

  def normalize_order(raw)
    normalizer.order(raw)
  end

  private

  def customers(search)
    nodes(query(CUSTOMERS_QUERY, first: SEARCH_LIMIT, query: search)['customers']).map { |raw| normalize_customer(raw) }
  end

  def guests(email)
    guest_orders = nodes(query(GUEST_ORDERS_QUERY, first: SEARCH_LIMIT, query: Commerce::Shopify::SearchQuery.email(email))['orders'])
    return [] unless guest_orders.any? { |raw| normalizer.guest_order?(raw, email) }

    [Commerce::Customer.new(external_id: "#{GUEST_PREFIX}#{email}", name: nil, emails: [email], phones: [], registered: false)]
  end

  def orders(search, first)
    nodes(query(ORDERS_QUERY, first: first, query: search)['orders'])
  end

  def nodes(connection)
    list = connection.is_a?(Hash) ? connection['nodes'] : nil
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless list.is_a?(Array) && list.all?(Hash)

    list
  end

  def query(document, variables)
    Commerce::Backoff.check!(backoff_key)
    tokens.with_credentials do |credentials|
      graphql = Commerce::Shopify::Graphql.new(shop, credentials['access_token'])
      graphql.query(document, variables)
    ensure
      Commerce::Backoff.record(backoff_key, graphql&.rate_limit)
    end
  end

  def backoff_key = "COMMERCE::SHOPIFY::MERCHANT::#{@store.external_store_id}::BACKOFF"

  def shop = URI(@store.base_url).host

  def tokens
    @tokens ||= Commerce::Shopify::TokenManager.new(@store)
  end

  def carts
    @carts ||= Carts.new(self, @store)
  end

  def normalizer
    @normalizer ||= Normalizer.new(self)
  end

  def actions
    @actions ||= Actions.new(self, @store)
  end

  def action_order(external_order_id)
    raw = query(ACTION_ORDER_QUERY, id: "gid://shopify/Order/#{Integer(external_order_id.to_s, 10)}")['order']
    raise Commerce::Error, 'NOT_FOUND' if raw.nil?

    raw
  end
end
