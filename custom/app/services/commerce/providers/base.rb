# The contract every commerce provider implements (docs/commerce/02-provider-contracts.md). Read-only by design:
# nothing here writes to a store. Every method returns provider-neutral values (Commerce::Customer, Commerce::Order)
# or raises Commerce::Error.
class Commerce::Providers::Base
  # Whether this installation offers the provider (see Commerce::Providers.enabled?).
  def self.enabled? = true

  def initialize(store, credentials:)
    @store = store
    @credentials = credentials
  end

  # Proves the store is reachable, speaks the expected API and that the credentials can read what we need.
  def health = raise(NotImplementedError)

  # { external_store_id:, name: } used for ownership (one account per store) and the default display name.
  def store_identity = raise(NotImplementedError)

  # Candidate customers for a verified email and/or E.164 phone. Candidates only: the matcher decides.
  def find_customers(email: nil, phone: nil) = raise(NotImplementedError)

  # Most recent orders of a linked customer, newest first.
  def list_customer_orders(external_customer_id, limit:) = raise(NotImplementedError)

  def get_order(external_order_id) = raise(NotImplementedError)

  # Built from the store's validated base URL and a validated order id, never from a URL in a provider response.
  def admin_order_url(external_order_id) = raise(NotImplementedError)

  # Removes what Lynomia set up in the store (webhook subscriptions) before a disconnect deletes the credentials.
  def release = nil

  # Realtime (docs/commerce/24-realtime-architecture.md). An order event of the store's webhooks names the customers
  # whose cached orders changed, as the store customer ids links keep (external_customer_id): [] when it names none, and
  # then every customer's cached orders of the store are dropped. Events never carry order data into Lynomia.
  def self.supports_realtime? = false

  def event_customer_ids(_payload) = []

  # The order an event is about, for logs and metrics only; nil when the event does not say.
  def event_order_id(_payload) = nil

  def normalize_customer(raw) = raise(NotImplementedError)

  def normalize_order(raw) = raise(NotImplementedError)
end
