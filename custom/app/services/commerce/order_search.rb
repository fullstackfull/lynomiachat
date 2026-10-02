# Finds orders by the number a customer quotes (docs/commerce/25-customer-360.md §order search), in the given stores.
# Each store is asked for that number directly (Providers::Base#find_orders), never scanned; stores of a provider without
# such a lookup are reported as not searchable. Stores are searched concurrently (Commerce::Parallel) and one failing or
# slow store is reported in its own entry. The orders may belong to any customer of the store, so they come back without
# their customer, and nothing is cached or linked.
#
# `owners` ({ store id => external customer id }) keeps only that customer's orders in each store: a customer asking
# for an order by number (a Lynomia flow) never receives another customer's order.
class Commerce::OrderSearch
  MAX_CONCURRENCY = 4
  STORE_TIMEOUT = 10

  def initialize(stores:, number:, owners: nil)
    @stores = stores
    @number = number
    @owners = owners
  end

  def call
    entries = Commerce::Parallel.map(@stores, concurrency: MAX_CONCURRENCY, timeout: STORE_TIMEOUT) { |store| search(store) }
    entries = @stores.zip(entries).map { |store, entry| entry || entry(store, 'unavailable', error: 'TIMEOUT') }
    orders = entries.flat_map { |entry| entry.delete(:orders) }.sort_by { |order| order['created_at'].to_s }.reverse
    { orders: orders, stores: entries, partial: entries.any? { |entry| entry[:error] } }
  end

  private

  def search(store)
    provider = Commerce::Providers.for(store)
    return entry(store, 'unsupported') unless provider.class.searches_orders?

    store_json = store.slice(:id, :name, :provider)
    orders = provider.find_orders(@number)
    orders = orders.select { |order| owned?(order, store) } if @owners
    entry(store, 'searched', orders: orders.map { |order| order.as_json.except('customer').merge('store' => store_json) })
  rescue Commerce::Error => e
    Commerce::StoreConnection.new(account: store.account, user: nil).credentials_rejected(store) if e.code == 'AUTH_INVALID'
    entry(store, 'unavailable', error: e.code)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: store.account).capture_exception
    entry(store, 'unavailable', error: 'STORE_UNAVAILABLE')
  end

  def owned?(order, store)
    owner = @owners[store.id].to_s
    owner.present? && order.customer.to_h.with_indifferent_access[:external_id].to_s == owner
  end

  def entry(store, state, orders: [], error: nil)
    { store: store.slice(:id, :name, :provider), state: state, error: error, orders: orders }
  end
end
