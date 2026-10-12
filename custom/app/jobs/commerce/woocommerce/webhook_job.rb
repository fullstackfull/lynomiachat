# Applies one authentic WooCommerce order event (Commerce::Woocommerce::Webhook) through Commerce::Realtime: the named
# customer's cached orders are dropped and refreshed. The event's order data is never kept.
class Commerce::Woocommerce::WebhookJob < ApplicationJob
  queue_as :default

  def perform(store_id, sealed_body)
    store = Commerce::Store.where.not(status: :disconnected).find_by(id: store_id, provider: 'woocommerce')
    payload = Commerce::WebhookQueue.unseal('woocommerce', sealed_body)
    return unless store && payload.is_a?(Hash)

    Commerce::Realtime.order_event(store, payload)
    # Applied, not merely received. The controller stamped receipt; this stamp staying behind it is how a stuck
    # queue becomes visible per store (docs/product-refinement/09-commerce-operations.md §webhooks).
    Commerce::StoreHealthRecorder.webhook_processed(store)
  end
end
