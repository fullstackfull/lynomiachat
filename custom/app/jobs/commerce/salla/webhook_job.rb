# Applies one verified Salla app event (see Commerce::Salla::Webhook). The argument is the encrypted event body.
#
# Salla or Redis being briefly unavailable is retried. Anything else (a malformed event, tokens with write scopes, tokens
# Salla rejects) cannot succeed on a retry, so it is reported once instead.
class Commerce::Salla::WebhookJob < ApplicationJob
  RETRYABLE_CODES = %w[STORE_UNAVAILABLE TIMEOUT RATE_LIMITED].freeze

  queue_as :default

  def perform(sealed_body)
    Commerce::Salla::Installation.new(Commerce::Salla::Webhook.unseal(sealed_body)).process
  rescue Commerce::Error => e
    raise if RETRYABLE_CODES.include?(e.code)

    ChatwootExceptionTracker.new(e).capture_exception
  end
end
