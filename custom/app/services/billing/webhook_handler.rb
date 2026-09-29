# frozen_string_literal: true

# Routes a verified Stripe event to the right sync logic.
module Billing
  class WebhookHandler
    SUBSCRIPTION_EVENTS = %w[
      customer.subscription.created
      customer.subscription.updated
      customer.subscription.deleted
    ].freeze

    def initialize(event)
      @event = event
    end

    def perform
      case @event.type
      when 'checkout.session.completed' then handle_checkout_completed
      when *SUBSCRIPTION_EVENTS then Billing::SubscriptionSync.new(object).perform
      else Rails.logger.info("[Billing] Ignored Stripe event #{@event.type}")
      end
    end

    private

    def object
      @event.data.object
    end

    def handle_checkout_completed
      return unless object.mode == 'subscription' && object.subscription.present?

      stripe_sub = Stripe::Subscription.retrieve(object.subscription, { api_key: Billing::Settings.stripe_secret_key })
      Billing::SubscriptionSync.new(stripe_sub, account_id: object.client_reference_id).perform
    end
  end
end