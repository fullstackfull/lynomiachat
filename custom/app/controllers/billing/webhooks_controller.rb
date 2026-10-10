# frozen_string_literal: true

# Receives Stripe webhooks: POST /billing/webhooks/stripe
#
# Lynomia (docs/p11/00-p10-security-closure.md, SEC-7). This endpoint used to pass
# `Billing::Settings.stripe_webhook_secret.to_s` to the Stripe SDK with no blank-secret guard. The SDK only
# requires the secret to be a String, so an unset secret became "" and `OpenSSL::HMAC` happily signed with an
# empty key -- which anyone can reproduce. A forged event then reached Billing::SubscriptionSync, which took
# the account from `client_reference_id` or `metadata['account_id']` checked only with `Account.exists?`, so a
# caller could name any account on the installation and move its subscription. The route is mounted
# unconditionally and does not consult Billing::Settings.enforced?, so this was open on exactly the
# installations that had not finished setting billing up.
#
# It now fails closed on a missing secret, the way app/controllers/webhooks/shopify_controller.rb already does.
#
# A processing failure still returns 500 so Stripe retries, but the retry is now idempotent: the event is
# claimed against a unique index first, and a redelivery is acknowledged without being processed again.
class Billing::WebhooksController < ActionController::API
  def stripe
    secret = Billing::Settings.stripe_webhook_secret
    return head :unauthorized if secret.blank?

    event = Stripe::Webhook.construct_event(request.body.read, request.headers['Stripe-Signature'], secret)
  rescue JSON::ParserError, Stripe::SignatureVerificationError => e
    Rails.logger.warn("[Billing] Rejected Stripe webhook: #{e.class}")
    head :bad_request
  else
    Billing::WebhookHandler.new(event).perform
    head :ok
  end
end
