# frozen_string_literal: true

# Routes a verified Stripe event to the right sync logic, exactly once (docs/p11/04-subscriptions-billing.md).
#
# Idempotency is the unique index on billing_webhook_events, not a flag or a cache: the event is claimed before
# any work happens, and a redelivery loses that insert and returns without doing anything. Stripe retries on
# every non-2xx and documents that it may deliver an event more than once of its own accord, so this is an
# ordinary occurrence rather than a hypothetical.
#
# A failure is recorded AND re-raised. The raise is what makes Stripe retry; the row and the operations signal
# are what make a repeated failure visible to an operator, which is what P11.44 asks for and what there was
# previously nothing to read.
class Billing::WebhookHandler
  PROVIDER = 'stripe'

  SUBSCRIPTION_EVENTS = %w[
    customer.subscription.created
    customer.subscription.updated
    customer.subscription.deleted
  ].freeze

  def initialize(event)
    @event = event
  end

  def perform
    receipt = BillingWebhookEvent.claim!(
      provider: PROVIDER, provider_event_id: @event.id, event_type: @event.type,
      provider_created_at: @event.created && Time.zone.at(@event.created)
    )
    if receipt.nil?
      Rails.logger.info("[Billing] Ignored a redelivery of Stripe event #{@event.type}")
      return
    end

    process(receipt)
  end

  private

  def process(receipt)
    subscription = dispatch
    if subscription
      receipt.succeeded!(subscription.account)
    else
      receipt.ignored!(ignored_reason)
    end
  rescue StandardError => e
    receipt.failed!(e)
    Billing::OperationsSignal.record_event_failure(nil, @event.type, e)
    raise
  end

  def dispatch
    case @event.type
    when 'checkout.session.completed' then handle_checkout_completed
    when *SUBSCRIPTION_EVENTS then sync(object)
    end
  end

  def ignored_reason
    return 'event type not handled' unless handled_type?

    'no account matched'
  end

  def handled_type?
    @event.type == 'checkout.session.completed' || SUBSCRIPTION_EVENTS.include?(@event.type)
  end

  def object
    @event.data.object
  end

  def sync(stripe_subscription, account_id: nil)
    result = Billing::SubscriptionSync.new(stripe_subscription, account_id: account_id,
                                                                event_at: @event.created && Time.zone.at(@event.created)).perform
    Billing::OperationsSignal.record_unknown_customer(event_type: @event.type) if result.nil?
    result
  end

  def handle_checkout_completed
    return nil unless object.mode == 'subscription' && object.subscription.present?

    stripe_sub = Stripe::Subscription.retrieve(object.subscription, { api_key: Billing::Settings.stripe_secret_key })
    sync(stripe_sub, account_id: object.client_reference_id)
  end
end
