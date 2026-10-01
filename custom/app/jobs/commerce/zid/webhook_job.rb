# Applies one authenticated Zid order event (see Commerce::Zid::Webhook) through Commerce::Realtime: the customer's cached
# orders are dropped and, for a linked contact, refreshed. Order events never write anything else, and an event naming
# another store is ignored.
class Commerce::Zid::WebhookJob < ApplicationJob
  queue_as :default

  def perform(store_id, sealed_body)
    store = Commerce::Store.find_by(id: store_id, provider: 'zid')
    payload = Commerce::WebhookQueue.unseal('zid', sealed_body)
    return unless store && payload.is_a?(Hash) && [nil, store.external_store_id].include?(payload['store_id']&.to_s)

    Commerce::Realtime.order_event(store, payload)
  end
end
