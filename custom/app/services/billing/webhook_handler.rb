# frozen_string_literal: true

# Routes a verified Stripe event to the right sync logic, exactly once (docs/p11/04-subscriptions-billing.md).
#
# Idempotency is the unique index on billing_webhook_events, not a flag or a cache: the event is claimed before
# any work happens, and a redelivery loses that insert and returns without doing anything. Stripe retries on
# every non-2xx and documents that it may deliver an event more than once of its own accord, so this is an
# ordinary occurrence rather than a hypothetical.
#
# ACCOUNTING EVENTS (invoice.*, charge.refunded, charge.dispute.created) are accepted here too, since the
# Odoo integration, but they are only ENQUEUED -- see #handle_accounting_event. Nothing in this request talks
# to Odoo.
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
    else handle_accounting_event
    end
  end

  # ACCOUNTING EXPORT, ENQUEUED AND NOT PERFORMED. Stripe expects an answer in milliseconds and retries
  # anything that is not a 2xx, so a synchronous call to the owner's Odoo here would turn one slow accounting
  # server into a storm of redeliveries -- which is why the Odoo brief forbids it. Odoo::EventRecorder inserts
  # one row per object and returns; Odoo::SyncJob does the work.
  #
  # Returns the queued row so `#process` can mark the receipt processed and name the account, or nil when
  # there is no Odoo destination configured -- in which case this installation behaves exactly as it did
  # before the integration existed.
  def handle_accounting_event
    return nil unless Odoo::EventRecorder.handled?(@event.type)

    events = Odoo::EventRecorder.new.record_webhook(@event)
    events.first.tap { |row| Odoo::SyncJob.perform_later(row.id) if row }
  end

  def ignored_reason
    return 'event type not handled' unless handled_type?

    'no account matched'
  end

  # Kept in step with `#dispatch` by construction: both ask the same three questions, so an event type added
  # to one cannot be accepted and then silently dropped by the other.
  def handled_type?
    @event.type == 'checkout.session.completed' || SUBSCRIPTION_EVENTS.include?(@event.type) ||
      Odoo::EventRecorder.handled?(@event.type)
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
