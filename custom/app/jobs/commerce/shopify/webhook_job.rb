# Applies one authenticated Shopify Commerce webhook (Commerce::Shopify::Webhook; docs/commerce/20-shopify-webhooks-and-
# compliance.md). Lynomia keeps no order database: per shop it keeps the store (encrypted token), customer links and
# cached reads, so that is all these events touch. Contacts and conversations are never deleted.
#
# - orders/create, orders/updated: through Commerce::Realtime, the customer's (or guest's) cached orders are dropped and,
#   for a linked contact, refreshed.
# - app/uninstalled: the store is disconnected: token, customer links and cache removed.
# - customers/redact: the customer's links and the store's cache are removed; the audit keeps counts only.
# - customers/data_request: recorded for the operator with the ids of the customer's links, so the data can be exported
#   for the merchant (docs/commerce/20 §4); nothing is removed.
# - shop/redact: the store row, its links and cache are deleted; the account's audit keeps the store id and counts.
# Shopify's headers are not signed, so the removals act only when the shop id in the signed body is the store's, and
# app/uninstalled and shop/redact are ignored for a store authorized again after the event was triggered.
class Commerce::Shopify::WebhookJob < ApplicationJob
  HANDLERS = {
    'orders/create' => :invalidate_orders, 'orders/updated' => :invalidate_orders, 'app/uninstalled' => :uninstalled,
    'customers/redact' => :redact_customer, 'customers/data_request' => :data_requested, 'shop/redact' => :redact_shop
  }.freeze

  queue_as :default

  def perform(topic, shop_domain, triggered_at, sealed_body)
    payload = Commerce::WebhookQueue.unseal('shopify', sealed_body)
    @store = Commerce::Store.find_by(provider: 'shopify', base_url: "https://#{shop_domain}")
    @triggered_at = triggered_at
    send(HANDLERS.fetch(topic), payload) if @store && payload.is_a?(Hash)
  end

  private

  def invalidate_orders(payload)
    Commerce::Realtime.order_event(@store, payload) unless @store.disconnected?
  end

  def uninstalled(payload)
    return unless shop?(payload['id']) && !@store.disconnected? && !authorized_since?

    Commerce::StoreConnection.new(account: @store.account, user: nil).disconnect(@store, event: 'commerce.shopify.uninstalled')
  end

  def redact_customer(payload)
    return unless shop?(payload['shop_id'])

    removed = customer_links(payload['customer']).delete_all
    Commerce::Cache.purge(@store)
    Commerce::AuditTrail.record('commerce.shopify.customer_redacted', auditable: @store, changes: { customer_links_removed: removed })
  end

  def data_requested(payload)
    return unless shop?(payload['shop_id'])

    changes = { customer_link_ids: customer_links(payload['customer']).pluck(:id), data_request_id: payload.dig('data_request', 'id') }
    Commerce::AuditTrail.record('commerce.shopify.customer_data_requested', auditable: @store, changes: changes)
  end

  def redact_shop(payload)
    return unless shop?(payload['shop_id']) && !authorized_since?

    changes = { store_id: @store.id, customer_links_removed: @store.customer_links.count }
    Commerce::Cache.purge(@store)
    Commerce::AuditTrail.record('commerce.shopify.shop_redacted', auditable: @store.account, changes: changes)
    @store.destroy!
  end

  # The links of a Shopify customer, registered (its id) or guest (its email).
  def customer_links(customer)
    customer = {} unless customer.is_a?(Hash)
    email = customer['email'].to_s.strip.downcase
    ids = [customer['id']&.to_s, email.presence && "#{Commerce::Providers::Shopify::GUEST_PREFIX}#{email}"].compact
    @store.customer_links.where(external_customer_id: ids)
  end

  def shop?(shop_id) = shop_id.to_s == @store.external_store_id

  def authorized_since?
    verified_at = @store.metadata['verified_at']
    verified_at.present? && @triggered_at.present? && Time.iso8601(verified_at) > Time.iso8601(@triggered_at)
  end
end
