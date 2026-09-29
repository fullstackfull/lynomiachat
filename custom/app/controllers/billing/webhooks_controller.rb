# frozen_string_literal: true

# Receives Stripe webhooks: POST /billing/webhooks/stripe
# Any error while processing returns 500, so Stripe retries the event later.
class Billing::WebhooksController < ActionController::API
  def stripe
    event = Stripe::Webhook.construct_event(
      request.body.read,
      request.headers['Stripe-Signature'],
      Billing::Settings.stripe_webhook_secret.to_s
    )
  rescue JSON::ParserError, Stripe::SignatureVerificationError => e
    Rails.logger.warn("[Billing] Rejected Stripe webhook: #{e.message}")
    head :bad_request
  else
    Billing::WebhookHandler.new(event).perform
    head :ok
  end
end
