# The provider-neutral order: the only order shape the API, the cache and the UI use (never raw provider JSON).
#
# status          pending | processing | on_hold | completed | cancelled | refunded | failed | draft | other
# payment_status  paid | unpaid | failed | refunded | partially_refunded | unknown (see each provider's normalizer)
# total, amounts  decimal strings in `currency`
# items           [{ name:, quantity:, total: }]
# shipping        { method:, total: } or nil when the order has no shipping line
# tracking        { number:, url: } or nil; never guessed
Commerce::Order = Data.define(
  :provider, :external_order_id, :order_number, :status, :provider_status, :payment_status, :currency, :total,
  :created_at, :updated_at, :items, :item_count, :customer, :shipping, :tracking, :admin_order_url, :customer_order_url
)
