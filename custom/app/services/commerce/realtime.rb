# Realtime Commerce (docs/commerce/24-realtime-architecture.md). A store's webhook only says that something changed; the
# store's API stays the source, and no event is kept as order data. After a provider's endpoint has authenticated and
# deduplicated a delivery:
#
#   1. the cached orders of the customers the event names are marked outdated (every customer's of the store when it names
#      none): the next read goes to the store, and they stay the stale fallback if it cannot answer;
#   2. for each contact linked to such a customer, one coalesced refresh (Commerce::RefreshJob) reads the orders again;
#   3. the refresh tells the account's agents through ActionCable (`commerce.customer.updated`: ids and a time only), and
#      an open Commerce section refetches the Commerce API, which authorizes as usual.
#
# Abandoned carts: every order event and every cart event (Salla abandoned.cart, abandoned.cart.update) drops the store's
# cached carts, so a cart an order completed is never shown again, not even as a stale fallback; the next view reads the
# store. A cart event refreshes the customer's linked contacts like an order event.
#
# Events arriving out of order need no handling: every refresh reads the current state from the store. The first event
# for a customer refreshes at once; any that arrive while that refresh is queued or running make exactly one more, after
# COALESCE_WINDOW, however many they are.
# COMMERCE_REALTIME_ENABLED=false (installation config or ENV) stops refreshes and broadcasts; cached orders are still
# marked outdated, so the next read or Refresh shows the change.
module Commerce::Realtime
  EVENT = 'commerce.customer.updated'.freeze
  COALESCE_WINDOW = 2.seconds
  LOCK_TTL = 1.minute

  def self.enabled?
    value = GlobalConfig.get_value('COMMERCE_REALTIME_ENABLED')
    ActiveModel::Type::Boolean.new.cast(value.nil? ? ENV.fetch('COMMERCE_REALTIME_ENABLED', 'true') : value) != false
  end

  # An authenticated, deduplicated order event of `store`, as its provider parsed it.
  def self.order_event(store, payload)
    provider = Commerce::Providers.for(store)
    customer_ids = provider.event_customer_ids(payload).compact_blank.map(&:to_s).uniq
    drop_carts(store)
    Commerce::Metrics.event('commerce.webhook.applied', provider: store.provider, store_id: store.id, customers: customer_ids.size)
    return Commerce::Cache.invalidate_all(store, :orders) if customer_ids.empty?

    customer_ids.each { |customer_id| Commerce::Cache.invalidate(store, :orders, customer_id) }
    return unless enabled? && store.active? && Commerce::Providers.enabled?(store.provider)

    store.customer_links.not_suppressed.where(external_customer_id: customer_ids).find_each { |link| schedule_refresh(link) }
  end

  def self.cart_event(store, payload)
    customer_ids = Commerce::Providers.for(store).event_customer_ids(payload).compact_blank.map(&:to_s).uniq
    drop_carts(store)
    Commerce::Metrics.event('commerce.cart.event', provider: store.provider, store_id: store.id, customers: customer_ids.size)
    return unless enabled? && store.active? && Commerce::Providers.enabled?(store.provider) && customer_ids.any?

    store.customer_links.not_suppressed.where(external_customer_id: customer_ids).find_each { |link| schedule_refresh(link) }
  end

  def self.drop_carts(store)
    Commerce::Cache.delete_all(store, :carts)
    Commerce::Cache.delete_all(store, :cart_queue)
  end

  def self.schedule_refresh(link)
    if Redis::Alfred.set(lock_key(link), 1, nx: true, ex: LOCK_TTL.to_i)
      Commerce::RefreshJob.perform_later(link.id)
    else
      Redis::Alfred.set(dirty_key(link), 1, ex: LOCK_TTL.to_i)
      Commerce::Metrics.event('commerce.refresh.coalesced', store_id: link.commerce_store_id, link_id: link.id)
    end
  end

  # Reads the linked customer's orders again (Commerce::RefreshJob) and tells the account's agents.
  def self.refresh(link)
    store = link.store
    Redis::Alfred.delete(dirty_key(link))
    read_orders(store, link) if store.active? && Commerce::Providers.enabled?(store.provider)
    broadcast(store.account_id, link.contact_id, store.id)
    rerun = Redis::Alfred.exists?(dirty_key(link))
    rerun ? requeue(store, link) : Redis::Alfred.delete(lock_key(link))
  rescue StandardError
    Redis::Alfred.delete(lock_key(link))
    raise
  end

  # Minimal by design: the receivers refetch through the Commerce API. Never order data, contact details or tokens.
  def self.broadcast(account_id, contact_id, store_id)
    return unless enabled?

    ActionCableBroadcastJob.perform_later(["account_#{account_id}"], EVENT,
                                          { account_id: account_id, contact_id: contact_id, store_id: store_id, updated_at: Time.current.iso8601 })
  end

  def self.read_orders(store, link)
    Commerce::Cache.fetch(store, :orders, link.external_customer_id) do
      Commerce::Providers.for(store).list_customer_orders(link.external_customer_id, limit: Commerce::ConversationPanel::ORDER_LIMIT)
    end
  rescue Commerce::Error => e
    Commerce::Metrics.event('commerce.provider.error', provider: store.provider, store_id: store.id, code: e.code)
    Commerce::StoreConnection.new(account: store.account, user: nil).credentials_rejected(store) if e.code == 'AUTH_INVALID'
  end

  # An event arrived while this refresh ran: its data may be older than the event, so read once more.
  def self.requeue(store, link)
    Commerce::Cache.invalidate(store, :orders, link.external_customer_id)
    Redis::Alfred.set(lock_key(link), 1, ex: LOCK_TTL.to_i)
    Commerce::RefreshJob.set(wait: COALESCE_WINDOW).perform_later(link.id)
  end

  # Kept apart from the cache's keys, so a refresh lock is never taken for cached data.
  def self.lock_key(link) = "COMMERCE::REFRESH::ACCOUNT::#{link.account_id}::STORE::#{link.commerce_store_id}::LINK::#{link.id}"

  def self.dirty_key(link) = "#{lock_key(link)}::PENDING"

  private_class_method :read_orders, :requeue, :lock_key, :dirty_key, :drop_carts
end
