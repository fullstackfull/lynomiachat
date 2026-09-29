# frozen_string_literal: true

# Cancels the account's Stripe subscription immediately (used before the
# account is deleted, so the customer is never charged for a deleted account).
#
# - Nothing to cancel (trial, manual, already canceled) -> returns quietly.
# - Subscription unknown / already canceled on Stripe  -> logs and returns.
# - Any other Stripe error (network, auth...)           -> raises, so the
#   deletion is aborted and the background job retries later.
class Billing::SubscriptionCanceller
  def initialize(subscription)
    @subscription = subscription
  end

  def perform
    return unless cancellable?

    Stripe::Subscription.cancel(@subscription.stripe_subscription_id, {}, { api_key: api_key })
    Rails.logger.info("[Billing] Canceled Stripe subscription #{@subscription.stripe_subscription_id} " \
                      "for account #{@subscription.account_id}")
  rescue Stripe::InvalidRequestError => e
    Rails.logger.warn("[Billing] Stripe subscription #{@subscription.stripe_subscription_id} " \
                      "not canceled (already ended?): #{e.message}")
  end

  private

  def api_key
    @api_key ||= Billing::Settings.stripe_secret_key
  end

  def cancellable?
    @subscription.present? &&
      @subscription.source == 'stripe' &&
      @subscription.stripe_subscription_id.present? &&
      @subscription.status != 'canceled' &&
      api_key.present?
  end
end
