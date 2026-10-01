# Customer 360 for a conversation's contact (docs/commerce/25-customer-360.md). The Chatwoot contact is the customer;
# each connected store contributes what Commerce::ConversationPanel shows for it (its link and latest orders), and this
# aggregates those views. Nothing is stored: the stores' APIs and the Redis cache stay the source, so every figure covers
# only the orders the stores returned (the latest ConversationPanel::ORDER_LIMIT per store), never a lifetime total.
#
# Stores are read concurrently (Commerce::Parallel), at most MAX_CONCURRENCY at a time, and the overview is answered
# after STORE_TIMEOUT whatever is still running: one slow or failing store is reported in its own entry and never fails
# the overview.
#
#   active order     status pending, processing, on_hold or shipped
#   shipped order    status shipped (handed to the carrier, not yet delivered)
#   last purchase    the newest order that is not a draft, failed or cancelled
#   spend            totals of orders the store reports as paid, per currency, never converted
class Commerce::Customer360
  LATEST_ORDERS = 10
  MAX_CONCURRENCY = 4
  STORE_TIMEOUT = 15
  ACTIVE_STATUSES = %w[pending processing on_hold shipped].freeze
  NOT_PURCHASES = %w[draft failed cancelled].freeze

  def initialize(conversation:, user:, force: false)
    @conversation = conversation
    @user = user
    @force = force
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    views = fetch(@conversation.account.commerce_stores.where(status: %i[active needs_reauth]).order(:created_at).to_a)
    summary(views, views.flat_map { |view| tagged_orders(view) }).tap do |result|
      Commerce::Metrics.event('commerce.customer360.load', account_id: @conversation.account_id, stores: views.size,
                                                           failed: result[:stores].count { |store| store[:error] },
                                                           ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
    end
  end

  private

  def summary(views, orders)
    {
      contact: { id: @conversation.contact_id },
      stores_count: views.size,
      linked_stores_count: views.count { |view| view[:state] == 'linked' },
      **order_figures(orders),
      stores: views.map { |view| view.except(:orders) },
      partial: views.any? { |view| view[:error].present? }
    }
  end

  # Each order names its store; the store's customer id and the customer's name are left out.
  def tagged_orders(view)
    (view[:orders] || []).map { |order| order.except('customer').merge('store' => view[:store]) }
  end

  def order_figures(orders)
    {
      orders_count_visible: orders.size,
      total_spend_visible: spend(orders),
      currencies: orders.filter_map { |order| order['currency'].presence }.uniq.sort,
      last_order_at: orders.reject { |order| NOT_PURCHASES.include?(order['status']) }.filter_map { |order| order['created_at'] }.max,
      active_orders_count: orders.count { |order| ACTIVE_STATUSES.include?(order['status']) },
      shipped_orders_count: orders.count { |order| order['status'] == 'shipped' },
      latest_orders: orders.sort_by { |order| order['created_at'].to_s }.reverse.first(LATEST_ORDERS)
    }
  end

  # Paid totals per currency as exact decimal strings; the panel formats them in the currency's own precision.
  def spend(orders)
    paid = orders.select { |order| order['payment_status'] == 'paid' && order['currency'].present? && order['total'].present? }
    paid.group_by { |order| order['currency'] }.sort.map do |currency, group|
      { currency: currency, amount: group.sum { |order| BigDecimal(order['total'].to_s) }.to_s('F') }
    end
  end

  def fetch(stores)
    views = Commerce::Parallel.map(stores, concurrency: MAX_CONCURRENCY, timeout: STORE_TIMEOUT) { |store| view(store) }
    stores.zip(views).map { |store, view| view || unavailable(store, 'TIMEOUT') }
  end

  # One store's entry: its state, link, freshness and orders. Stores of a provider the installation switched off, and
  # stores waiting for re-authorization, are listed without being read and without cached data.
  def view(store)
    return base(store).merge(state: 'provider_unavailable') unless Commerce::Providers.enabled?(store.provider)
    return base(store).merge(state: 'needs_reauth') if store.needs_reauth?

    panel = Commerce::ConversationPanel.new(store: store, conversation: @conversation, user: @user).show(force: @force)
    base(store).merge(panel.slice(:state, :link, :fetched_at, :stale, :error), orders: panel[:orders], orders_count: panel[:orders]&.size)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    unavailable(store, 'STORE_UNAVAILABLE')
  end

  def unavailable(store, code) = base(store).merge(state: 'unavailable', error: code)

  def base(store)
    { store: { id: store.id, name: store.name, provider: store.provider }, link: nil, fetched_at: nil, stale: false, error: nil, orders_count: nil }
  end
end
