# The provider-neutral order: the only order shape the API, the cache and the UI use (never raw provider JSON).
#
# status          pending | processing | on_hold | shipped | delivered | completed | cancelled | refunded | failed | draft
#                 | other
# payment_status  paid | unpaid | failed | refunded | partially_refunded | unknown (see each provider's normalizer)
# total, amounts  decimal strings in `currency`
# items           [{ name:, quantity:, total: }]; item_count is nil when the provider did not send the items
# shipping        { method:, total:, provider:, status: } (keys a provider does not know are nil), or nil
# shipments       [{ provider:, status:, provider_status:, type:, tracking_number:, tracking_url: }]; status is
#                 pending | in_transit | out_for_delivery | delivered | failed | cancelled | returned | other
# tracking        { number:, url: } of the order's main shipment, or nil; never guessed
Commerce::Order = Data.define(
  :provider, :external_order_id, :order_number, :status, :provider_status, :payment_status, :currency, :total,
  :created_at, :updated_at, :items, :item_count, :customer, :shipping, :shipments, :tracking, :admin_order_url, :customer_order_url
)
