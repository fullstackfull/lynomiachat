# Shopify abandoned checkouts (docs/commerce/30-abandoned-carts.md §Shopify): GraphQL `abandonedCheckouts` only (2026-07,
# read_orders), open checkouts, newest first. Shopify has no customer filter for them, so the most recent page is read
# and Commerce::AbandonedCarts keeps only the conversation's linked customer's checkouts.
#
# Identity: only the customer's id. No email, phone or address is requested (protected customer data): a guest checkout
# never matches. A checkout with completedAt is recovered.
class Commerce::Providers::Shopify::Carts
  ITEM_LIMIT = 10
  FIELDS = <<~GRAPHQL.freeze
    id name abandonedCheckoutUrl createdAt updatedAt completedAt lineItemsQuantity customer { id }
    totalPriceSet { presentmentMoney { amount currencyCode } }
    lineItems(first: #{ITEM_LIMIT}) { nodes { title quantity } }
  GRAPHQL
  QUERY = <<~GRAPHQL.freeze
    query LynomiaAbandonedCheckouts($first: Int!, $query: String!) {
      abandonedCheckouts(first: $first, query: $query, sortKey: CREATED_AT, reverse: true) { nodes { #{FIELDS} } }
    }
  GRAPHQL
  DOMAIN_QUERY = 'query LynomiaShopDomain { shop { primaryDomain { host } } }'.freeze
  CUSTOMER_GID = %r{\Agid://shopify/Customer/(\d+)\z}
  CHECKOUT_GID = %r{\Agid://shopify/AbandonedCheckout/(\d+)\z}

  def initialize(provider, store)
    @provider = provider
    @store = store
  end

  # Open checkouts, newest first: Shopify cannot filter them by customer.
  def recent(limit)
    nodes(@provider.read(QUERY, first: limit, query: 'status:open')).map { |raw| normalize(raw) }
  end

  # Open or not: a recovered checkout must be seen as recovered, never offered again.
  def find(external_cart_id)
    id = Integer(external_cart_id.to_s, 10)
    raw = nodes(@provider.read(QUERY, first: 1, query: "id:#{id}")).first
    raise Commerce::Error, 'NOT_FOUND' if raw.nil?

    normalize(raw)
  rescue ArgumentError
    raise Commerce::Error, 'NOT_FOUND'
  end

  # Where Shopify's recovery links point besides the myshopify.com host.
  def primary_domain = @provider.read(DOMAIN_QUERY).dig('shop', 'primaryDomain', 'host')

  def normalize(raw)
    Commerce::AbandonedCart.new(
      provider: 'shopify', store_id: @store.id, external_cart_id: raw.fetch('id').to_s[CHECKOUT_GID, 1] || raise(ArgumentError, 'checkout id'),
      created_at: raw['createdAt'], updated_at: raw['updatedAt'], **money(raw.dig('totalPriceSet', 'presentmentMoney')), items: items(raw),
      customer_reference: raw.dig('customer', 'id').to_s[CUSTOMER_GID, 1], email: nil, phone: nil,
      recovery_url: raw['abandonedCheckoutUrl'].to_s.presence, provider_metadata: { 'name' => raw['name'] }.compact,
      status: raw['completedAt'].present? ? 'recovered' : 'abandoned', recovered_at: raw['completedAt']
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_cart')
  end

  private

  def money(value)
    value = {} unless value.is_a?(Hash)
    { currency: value['currencyCode'].to_s.presence, total: value['amount'].nil? ? nil : BigDecimal(value['amount'].to_s).to_s('F') }
  end

  def items(raw)
    Array(raw.dig('lineItems', 'nodes')).map { |item| { name: item['title'].to_s.presence, quantity: Integer(item.fetch('quantity').to_s, 10) } }
  end

  def nodes(data)
    list = data.dig('abandonedCheckouts', 'nodes') if data.is_a?(Hash) && data['abandonedCheckouts'].is_a?(Hash)
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'unexpected_shape') unless list.is_a?(Array) && list.all?(Hash)

    list
  end
end
