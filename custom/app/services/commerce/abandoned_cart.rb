# The provider-neutral abandoned cart (docs/commerce/30-abandoned-carts.md): the only cart shape the API, the cache and
# the UI use. Read from the store when needed and kept in the Redis cache only, never in Postgres.
#
# status              abandoned | recovered (bought since) | expired (older than Commerce::AbandonedCarts::MAX_AGE) | unknown
# total               decimal string in `currency`
# items               [{ name:, quantity: }], names nil when the store sends none
# customer_reference  the store's customer id, as customer links keep it, or nil for a guest
# email, phone        the cart's own contact details, normalized; nil when absent or masked. Used only to match the cart
#                     to the conversation's verified identity, never shown
# recovery_url        the store's own link back to the cart; validated by Commerce::RecoveryUrl before an agent gets it
# provider_metadata   a few provider facts for display (checkout phase, reminders sent), never a payload
Commerce::AbandonedCart = Data.define(
  :provider, :store_id, :external_cart_id, :created_at, :updated_at, :currency, :total, :items, :customer_reference, :email,
  :phone, :recovery_url, :status, :recovered_at, :provider_metadata
)
