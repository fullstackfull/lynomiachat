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
    Commerce::Realtime.order_event(store, payload) if store
  end

  def cart_event(payload)
    store = event_store(payload)
    Commerce::Realtime.cart_event(store, payload) if store
  end

  def event_store(payload)
    Commerce::Store.where.not(status: :disconnected).find_by(provider: 'salla', external_store_id: payload['merchant'].to_s)
  end
end
