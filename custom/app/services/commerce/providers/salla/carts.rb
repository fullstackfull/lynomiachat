# Salla abandoned carts (docs/commerce/30-abandoned-carts.md §Salla), from the Merchant API's abandoned carts list
# (`GET /admin/v2/carts/abandoned`, scope carts.read) in the shape of Salla's official Cart resource (@salla.sa types:
# id, checkout_url, total, created_at/updated_at, customer, items). The list path and scope come from Salla's API map
# (docs/commerce/05): VERIFY on a live store. Salla's list has no documented customer filter, so its most recent page is
# read and Commerce::AbandonedCarts keeps only the conversation's customer's carts.
#
# Items carry product ids and quantities, no names. A listed cart is abandoned; a cart Salla no longer lists has been
# bought or removed, and is not offered for recovery. Masked contact details never match.
class Commerce::Providers::Salla::Carts
  SCOPE = 'carts.read'.freeze

  def initialize(store)
    @store = store
  end

  def normalize(raw)
    Commerce::AbandonedCart.new(
      provider: 'salla', store_id: @store.id, external_cart_id: positive_id(raw.fetch('id')), created_at: time(raw['created_at']),
      updated_at: time(raw['updated_at']), **money(raw['total']),
      items: Array(raw['items']).map { |item| { name: nil, quantity: Integer(item.fetch('quantity').to_s, 10) } },
      recovery_url: raw['checkout_url'].to_s.presence, status: 'abandoned', recovered_at: nil,
      provider_metadata: { 'age_in_minutes' => raw['age_in_minutes'] }.compact, **identity(raw['customer'])
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'malformed_cart')
  end

  private

  def identity(customer)
    customer = {} unless customer.is_a?(Hash)
    { customer_reference: customer['id'].present? ? positive_id(customer['id']) : nil, email: email(customer['email']),
      phone: phone(customer['mobile']) }
  end

  def time(value)
    return if value.blank?

    zone = ActiveSupport::TimeZone[value.fetch('timezone').to_s] || raise(ArgumentError, 'unknown time zone')
    zone.parse(value.fetch('date').to_s).utc.iso8601
  end

  def money(total)
    total = {} unless total.is_a?(Hash)
    { currency: total['currency'].to_s.presence, total: total['amount'].nil? ? nil : BigDecimal(total['amount'].to_s).to_s('F') }
  end

  def email(value)
    email = value.to_s.strip.downcase
    email if email.present? && email.exclude?('*')
  end

  def phone(value)
    value.to_s.include?('*') ? nil : Commerce::Phone.e164(value.to_s.strip)
  end

  def positive_id(value)
    id = Integer(value.to_s, 10)
    raise ArgumentError, 'id must be positive' unless id.positive?

    id.to_s
  end
end
