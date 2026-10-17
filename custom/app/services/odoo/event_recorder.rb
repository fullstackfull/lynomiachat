# Turning a Stripe notification into queued accounting work (docs/odoo/02-architecture.md §6).
#
# THE WEBHOOK'S WHOLE CONTRIBUTION IS AN INSERT. The brief forbids a synchronous Odoo call inside a Stripe
# webhook handler, and it is right to: Stripe expects an answer in milliseconds and retries anything that is
# not a 2xx, so an endpoint that waited on a third-party accounting server would turn one slow Odoo into a
# storm of redeliveries. So this records the fact and returns.
#
# IT RECORDS AN ID, NOT A PAYLOAD. The row carries the Stripe object's id and nothing more, because a worker
# running two minutes later must describe what the invoice IS rather than what a notification said it was.
#
# THE DEDUP KEY is scoped exactly like a document mapping's idempotency key, so a Stripe redelivery, a second
# webhook about the same object, and a historical import covering a period live sync already handled all
# collapse onto one row -- which is what keeps a backfill from producing a second accounting document.
class Odoo::EventRecorder
  # The Stripe event types this integration acts on. Everything else is somebody else's business: a
  # subscription event changes entitlement rather than money, and Billing::WebhookHandler already owns it.
  INVOICE_EVENTS = %w[invoice.paid invoice.finalized invoice.payment_failed invoice.voided
                      invoice.marked_uncollectible].freeze
  REFUND_EVENTS = %w[charge.refunded].freeze
  DISPUTE_EVENTS = %w[charge.dispute.created].freeze

  HANDLED = (INVOICE_EVENTS + REFUND_EVENTS + DISPUTE_EVENTS).freeze

  def self.handled?(event_type)
    HANDLED.include?(event_type.to_s)
  end

  def initialize(profile = Odoo::DestinationProfile.active, source: nil)
    @profile = profile
    @source = source || Odoo::StripeSource.new
  end

  # Returns the enqueued rows, newest intent first, or [] when there is no destination configured or the event
  # is not one of ours. The absence of a destination is NOT an error: an installation that has not set Odoo up
  # must keep taking Stripe webhooks exactly as it did before this feature existed.
  def record_webhook(event)
    return [] if @profile.nil? || !self.class.handled?(event.type)

    object = event.data.object
    case event.type
    when *INVOICE_EVENTS then [enqueue(event, 'invoice', object.id, customer_of(object))]
    when *REFUND_EVENTS then refund_rows(event, object)
    when *DISPUTE_EVENTS then [enqueue(event, 'dispute', object.id, nil)]
    end.compact
  end

  # The operator-initiated path: a historical import, or a retry of one row. Same table, same dedup key, same
  # worker -- which is the brief's requirement that a backfill reuse the idempotency engine rather than get
  # its own.
  def record_backfill(provider_object_type:, provider_object_id:, account_id: nil, event_type: 'backfill')
    return nil if @profile.nil?

    enqueue_row(event_type: event_type, provider_object_type: provider_object_type, origin: 'backfill',
                provider_object_id: provider_object_id, account_id: account_id)
  end

  private

  # ONE EVENT PER REFUND. A `charge.refunded` notification carries every refund the charge has ever had, so a
  # customer refunded twice produces two rows -- and the second notification's first refund lands on the dedup
  # key the first notification already used, so it is not done twice.
  def refund_rows(event, charge)
    Array(charge.refunds&.data).map { |refund| enqueue(event, 'refund', refund.id, customer_of(charge)) }
  end

  def enqueue(event, provider_object_type, provider_object_id, account_id)
    enqueue_row(event_type: event.type, provider_object_type: provider_object_type, origin: 'webhook',
                provider_object_id: provider_object_id, account_id: account_id, provider_event_id: event.id)
  end

  # Takes the row's attributes as one hash rather than six keywords: the caller is describing a record, and
  # this adds the three fields that are the same for every one of them plus the dedup key it derives.
  def enqueue_row(attributes)
    key = [@profile.source_app, @profile.environment, 'stripe', attributes[:provider_object_type],
           attributes[:provider_object_id], "profile_#{@profile.id}"].join(':')
    row = { destination_profile: @profile, provider: 'stripe', dedup_key: key, state: :pending }.merge(attributes)
    Odoo::SyncEvent.enqueue(row) || Odoo::SyncEvent.find_by(dedup_key: key)
  end

  # Resolved from OUR OWN stored mapping, never from the body's metadata -- the same rule
  # Billing::SubscriptionSync follows, for the same reason. nil is a legitimate answer and the worker reports
  # it as `unknown_stripe_customer` rather than guessing.
  def customer_of(object)
    id = object.customer.is_a?(String) ? object.customer : object.customer&.id
    @source.account_for_customer(id)&.id
  end
end
