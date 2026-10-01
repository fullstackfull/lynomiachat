# The contract every commerce provider implements (docs/commerce/02-provider-contracts.md). Reads, plus the order
# actions below (docs/commerce/29-provider-action-capabilities.md), which are the only writes to a store. Every method
# returns provider-neutral values (Commerce::Customer, Commerce::Order) or raises Commerce::Error.
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

  # Order search (docs/commerce/25-customer-360.md §order search): the store's orders whose number, as the panel shows
  # it, is exactly `number` (digits). Each provider asks the store for that number directly and never scans its orders;
  # providers without such a lookup are reported as not searchable.
  def self.searches_orders? = false

  # For stores that number orders by their id: the order with that id, kept only when its number is the one asked for.
  def find_orders(number)
    [get_order(number)].select { |order| order.order_number == number }
  rescue Commerce::Error => e
    raise unless e.code == 'NOT_FOUND'

    []
  end

  # Built from the store's validated base URL and a validated order id, never from a URL in a provider response.
  def admin_order_url(external_order_id) = raise(NotImplementedError)

  # Removes what Lynomia set up in the store (webhook subscriptions) before a disconnect deletes the credentials.
  def release = nil

  # Realtime (docs/commerce/24-realtime-architecture.md). An order event of the store's webhooks names the customers
  # whose cached orders changed, as the store customer ids links keep (external_customer_id): [] when it names none, and
  # then every customer's cached orders of the store are dropped. Events never carry order data into Lynomia.
  def self.supports_realtime? = false

  # Providers whose webhooks Lynomia creates with the store's own credentials, after each new authorization
  # (Commerce::WebhookRegistrationJob). Zid registers from its authorization flow; Salla and Shopify from their app setup.
  def self.registers_webhooks? = false

  def register_webhooks = nil

  def event_customer_ids(_payload) = []

  # The order an event is about, for logs and metrics only; nil when the event does not say.
  def event_order_id(_payload) = nil

  # Order actions (docs/commerce/29-provider-action-capabilities.md): the only writes a provider makes, and only through
  # Commerce::OrderActions, which checks switches, permissions, idempotency and the order's version first. A provider
  # implements just the actions its store API supports for certain; every other action is reported unsupported.
  def self.supports_actions? = false

  # nil when the store's credentials can change orders, else why not: 'read_only_key' (a WooCommerce Read key),
  # 'missing_scope' (Shopify without write_orders). Credentials are never upgraded silently: an administrator does it.
  def write_access_problem = 'unsupported'

  # The order read from the store now, with what each action could do to it (Commerce::ActionSnapshot).
  def action_snapshot(_external_order_id) = raise(NotImplementedError)

  # Sends one action to the store, once; never retried here. `params` are validated by Commerce::OrderActions and
  # checked against `snapshot`. Returns a Commerce::ActionResult; a lost answer raises Commerce::Error with reason
  # 'unknown_outcome'.
  def perform_action(_action_type, _snapshot, _params, _idempotency_key) = raise(NotImplementedError)

  # After a lost answer (or an asynchronous store job): whether the action took effect, judged only by reading the store
  # (`snapshot` is fresh). Never sends the action again. Returns a Commerce::ActionResult: succeeded, failed (provably not
  # applied, safe to ask again) or unknown.
  def reconcile_action(_run, _snapshot) = Commerce::ActionResult.unknown('NOT_RECONCILABLE')

  def normalize_customer(raw) = raise(NotImplementedError)

  def normalize_order(raw) = raise(NotImplementedError)
end
