# Applies one authenticated Zid event (see Commerce::Zid::Webhook), and nothing else writes from a Zid delivery.
#
#   an abandoned-cart event  Commerce::Providers::Zid::CartEvents normalizes it and Commerce::CartLifecycle records the
#                            cart's durable lifecycle; the cached carts are dropped so the viewer re-reads
#   an order event           Commerce::Realtime as before: the customer's cached orders are dropped and, for a linked
#                            contact, refreshed. Lynomia keeps no order database
#
# Both kinds arrive at the same endpoint, so the event name routes them. A delivery that carries no event name is
# treated as an order event, which is what this job has always done; a cart-shaped body without one is NOT guessed at,
# because filing a cart as an order is worse than refusing one delivery loudly.
class Commerce::Zid::WebhookJob < ApplicationJob
  queue_as :default

  def perform(store_id, sealed_body)
    store = Commerce::Store.find_by(id: store_id, provider: 'zid')
    payload = Commerce::WebhookQueue.unseal('zid', sealed_body)
    return unless store && payload.is_a?(Hash) && [nil, store.external_store_id].include?(payload['store_id']&.to_s)

    Commerce::Providers::Zid::CartEvents.cart_delivery?(payload) ? cart_event(store, payload) : Commerce::Realtime.order_event(store, payload)
  end

  private

  def cart_event(store, payload)
    event = Commerce::Providers::Zid::CartEvents.new(payload).event
    return report_unusable(store, payload) if event.nil?

    Commerce::CartLifecycle.new(store).apply(event)
    # The read-through viewer must not keep showing a cart whose state just changed.
    Commerce::Realtime.cart_event(store, payload)
  end

  # A cart delivery Lynomia cannot place: no usable identity under Commerce::Providers::Zid::CartEvents::IDENTITY_KEY,
  # or no provider timestamp to order it by. Reported rather than dropped silently, because this is exactly what a
  # wrong UNVERIFIED assumption in the normalizer would look like on a real store.
  def report_unusable(store, payload)
    Rails.logger.error(
      "[COMMERCE CART] event=unusable_zid_cart_delivery store_id=#{store.id} " \
      "zid_event=#{Commerce::Providers::Zid::CartEvents.event_name(payload)} keys=#{payload.keys.sort.join(',')}"
    )
    Commerce::Metrics.event('commerce.cart.unusable_delivery', provider: 'zid', store_id: store.id)
  end
end
