# Applies one verified Salla app event (see Commerce::Salla::Webhook). The argument is the encrypted event body.
#
# Salla or Redis being briefly unavailable is retried. Anything else (a malformed event, tokens with write scopes, tokens
# Salla rejects) cannot succeed on a retry, so it is reported once instead.
class Commerce::Salla::WebhookJob < ApplicationJob
  RETRYABLE_CODES = %w[STORE_UNAVAILABLE TIMEOUT RATE_LIMITED].freeze

  queue_as :default

  # Store events (orders, shipments, abandoned carts) go to Commerce::Realtime for the store of the event's merchant;
  # everything else is an app event (Commerce::Salla::Installation). VERIFY(salla-store-events): event names as subscribed
  # in the Partner Portal.
  STORE_EVENT_PREFIXES = %w[order. shipment.].freeze
  CART_EVENTS = %w[abandoned.cart abandoned.cart.update].freeze

  def perform(sealed_body)
    payload = Commerce::Salla::Webhook.unseal(sealed_body)
    return store_event(payload) if payload.is_a?(Hash) && payload['event'].to_s.start_with?(*STORE_EVENT_PREFIXES)
    return cart_event(payload) if payload.is_a?(Hash) && CART_EVENTS.include?(payload['event'].to_s)

    Commerce::Salla::Installation.new(payload).process
  rescue Commerce::Error => e
    raise if RETRYABLE_CODES.include?(e.code)

    ChatwootExceptionTracker.new(e).capture_exception
  end

  private

  def store_event(payload)
    store = event_store(payload)
    return if store.nil?

    Commerce::Realtime.order_event(store, payload)
    Commerce::StoreHealthRecorder.webhook_processed(store)
  end

  def cart_event(payload)
    store = event_store(payload)
    return if store.nil?

    Commerce::Realtime.cart_event(store, payload)
    Commerce::StoreHealthRecorder.webhook_processed(store)
  end

  # Salla's signature was checked at the request (Webhooks::SallaController) but the delivery names its merchant
  # in the signed BODY, so this is the first point that knows which store is healthy
  # (docs/product-refinement/09-commerce-operations.md §webhooks).
  def event_store(payload)
    store = Commerce::Store.where.not(status: :disconnected).find_by(provider: 'salla', external_store_id: payload['merchant'].to_s)
    Commerce::StoreHealthRecorder.webhook_received(store) if store
    store
  end
end
