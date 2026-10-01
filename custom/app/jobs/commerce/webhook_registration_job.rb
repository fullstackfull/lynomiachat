# Creates a store's webhooks after it was connected, its keys replaced, or it was enabled again, for providers whose
# webhooks Lynomia creates with the store's own credentials (Commerce::Providers::Base.registers_webhooks?). The store or
# Redis being briefly unavailable is retried; anything else is reported once. The store works without its webhooks
# meanwhile: cached orders are refreshed after two minutes, or on request.
class Commerce::WebhookRegistrationJob < ApplicationJob
  RETRYABLE_CODES = %w[STORE_UNAVAILABLE TIMEOUT RATE_LIMITED].freeze

  queue_as :default

  def perform(store_id)
    store = Commerce::Store.find_by(id: store_id)
    Commerce::Providers.for(store).register_webhooks if store&.active? && Commerce::Providers.enabled?(store.provider)
  rescue Commerce::Error => e
    raise if RETRYABLE_CODES.include?(e.code)

    ChatwootExceptionTracker.new(e, account: store&.account).capture_exception
  end
end
