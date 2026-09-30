# Subscribes a newly connected or re-authorized Zid store to its order events (Commerce::Zid::Webhooks#register). Zid or
# Redis being briefly unavailable is retried; anything else cannot succeed on a retry and is reported once. The store
# works without its webhooks meanwhile, since cached orders are refreshed after two minutes anyway.
class Commerce::Zid::WebhookRegistrationJob < ApplicationJob
  RETRYABLE_CODES = %w[STORE_UNAVAILABLE TIMEOUT RATE_LIMITED].freeze

  queue_as :default

  def perform(store_id)
    store = Commerce::Store.find_by(id: store_id, provider: 'zid')
    Commerce::Zid::Webhooks.new(store).register if store&.active?
  rescue Commerce::Error => e
    raise if RETRYABLE_CODES.include?(e.code)

    ChatwootExceptionTracker.new(e).capture_exception
  end
end
