# Applies one authentic Store Syria commerce event through Commerce::Realtime: the customer the
# event names has their cached orders dropped and refreshed. The event's contents are never kept
# as order data -- the store stays the source, which is also why an event arriving out of order
# needs no handling.
class Commerce::Storesyria::WebhookJob < ApplicationJob
  queue_as :default

  def perform(store_id, sealed_body)
    store = Commerce::Store.where.not(status: :disconnected).find_by(id: store_id, provider: 'storesyria')
    payload = Commerce::WebhookQueue.unseal('storesyria', sealed_body)
    return unless store && payload.is_a?(Hash)

    Commerce::Realtime.order_event(store, payload)
    # Applied, not merely received. The controller stamped receipt; this stamp staying behind it
    # is how a stuck queue becomes visible per store.
    Commerce::StoreHealthRecorder.webhook_processed(store)
  end
end
