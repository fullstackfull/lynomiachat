# Applies one authenticated Zid order event (see Commerce::Zid::Webhook): the customer's cached orders are dropped, so
# the next read of the conversation panel fetches them from Zid. Order events never write anything else, and an event
# naming another store is ignored.
class Commerce::Zid::WebhookJob < ApplicationJob
  queue_as :default

  def perform(store_id, sealed_body)
    store = Commerce::Store.find_by(id: store_id, provider: 'zid')
    payload = Commerce::Zid::Webhook.unseal(sealed_body)
    return unless store && payload.is_a?(Hash) && [nil, store.external_store_id].include?(payload['store_id']&.to_s)

    customer_id = payload['customer'].is_a?(Hash) ? payload['customer']['id'] : nil
    Commerce::Cache.invalidate(store, :orders, customer_id.to_s) if customer_id
  end
end
