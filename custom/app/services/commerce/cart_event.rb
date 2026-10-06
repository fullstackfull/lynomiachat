# One provider-neutral cart lifecycle event (docs/commerce-production/06-cart-transition-design.md).
#
# This is the only cart shape Commerce::CartLifecycle ever sees. A provider normalizer builds it — for Zid,
# Commerce::Providers::Zid::CartEvents — so the lifecycle has no knowledge of any provider's field names, and
# resolving Zid's cart-identity question after a real UAT changes one normalizer and nothing else.
#
#   kind                :abandoned (the provider says this cart was abandoned) or :completed (the provider says the
#                       cart was completed). Nothing else: see Commerce::Cart for why there is no :recovered.
#   provider_cart_id    the provider's own identifier for the cart, already chosen by the normalizer. Never a
#                       concatenation of identifiers.
#   occurred_at         the PROVIDER's timestamp for this event. The monotonic guard compares against this, never
#                       against Lynomia's clock, so a redelivery days later cannot look newer than what it carries.
#   phase               the provider's own funnel position, verbatim, for display and diagnostics. Never interpreted
#                       as lifecycle state.
#   order_reference     the provider's order id when the provider itself correlated the cart to an order, else nil.
#                       Lynomia never infers it.
Commerce::CartEvent = Data.define(
  :kind, :provider_cart_id, :occurred_at, :first_seen_at, :phase, :currency, :total, :item_count,
  :customer_reference, :order_reference
) do
  def abandoned? = kind == :abandoned
  def completed? = kind == :completed
end
