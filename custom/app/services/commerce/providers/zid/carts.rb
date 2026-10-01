# Zid abandoned carts (docs/commerce/30-abandoned-carts.md §Zid), as Zid's official SDK reads them:
# `GET /v1/managers/store/abandoned-carts` (page and page_size required, filter customer_id, results under
# "abandoned-carts") and `GET .../abandoned-carts/{id}` (under "abandoned_cart", with products). Scope
# abandoned_carts.read. Zid's notification (reminder) API is never used: Lynomia only prepares a message for an agent.
#
# Status: phase "completed", or an order made from the cart, is recovered; any other phase is abandoned. Masked contact
# details ("t***@…") never match.
class Commerce::Providers::Zid::Carts
  CART_ID = /\A[0-9a-f-]{8,64}\z/i

  def initialize(store, normalizer)
    @store = store
    @normalizer = normalizer
  end

  def normalize(raw)
    Commerce::AbandonedCart.new(
      provider: 'zid', store_id: @store.id, external_cart_id: cart_id(raw.fetch('id')), created_at: @normalizer.cart_time(raw['created_at']),
      updated_at: @normalizer.cart_time(raw['updated_at']), currency: raw['currency_code'].to_s.presence, total: total(raw), items: items(raw),
      recovery_url: raw['url'].to_s.presence, provider_metadata: { 'phase' => raw['phase'], 'reminders_count' => raw['reminders_count'] }.compact,
      **identity(raw), **status(raw)
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_cart')
  end

  def cart_id(value)
    id = value.to_s
    raise ArgumentError, 'invalid cart id' unless id.match?(CART_ID)

    id
  end

  private

  def total(raw) = raw['cart_total'].nil? ? nil : BigDecimal(raw['cart_total'].to_s).to_s('F')

  def identity(raw)
    { customer_reference: raw['customer_id'].present? ? Integer(raw['customer_id'].to_s, 10).to_s : nil,
      email: @normalizer.cart_email(raw['customer_email']), phone: @normalizer.cart_phone(raw['customer_mobile']) }
  end

  def status(raw)
    recovered = raw['phase'].to_s == 'completed' || raw['order_id'].present?
    { status: recovered ? 'recovered' : 'abandoned', recovered_at: recovered ? @normalizer.cart_time(raw['updated_at']) : nil }
  end

  # The detail lists products with names; the list gives only their count.
  def items(raw)
    if raw['products']
      return Array(raw['products']).map { |item| { name: item['name'].to_s.presence, quantity: Integer(item.fetch('quantity').to_s, 10) } }
    end

    count = raw['products_count'].to_i
    count.positive? ? [{ name: nil, quantity: count }] : []
  end
end
