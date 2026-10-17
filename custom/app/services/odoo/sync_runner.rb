# Drains one queued piece of accounting work (docs/odoo/02-architecture.md §6).
#
# WHAT IT OWNS. Claiming the row so two workers cannot do it twice, choosing the exporter, recording the
# attempt BEFORE the write goes out, and deciding from the attempt's outcome whether the row retries, fails,
# blocks or goes to a person. The exporters own the accounting; this owns the state machine.
#
# THE ATTEMPT IS RECORDED FIRST, and that ordering is the whole point. If the attempt were recorded after the
# call, a worker killed mid-write would leave no evidence the write was ever sent -- and a crash mid-write is
# then indistinguishable from a write that never happened, while the correct recovery for the two is opposite.
# With the row written first, the next attempt can see that attempt 1 went out with an unknown outcome and
# search Odoo for the stamp instead of writing again.
#
# IT NEVER RAISES INTO SIDEKIQ for a failure it has classified. A classified failure is recorded on the row and
# the job returns, because Sidekiq's own retry would run the same work on a different schedule from the one
# this table holds, and an operator reading `run_after` would be reading a lie. Only an unclassified exception
# is allowed out, where it belongs: in the error tracker.
class Odoo::SyncRunner
  # Which exporter handles which Stripe object. One table rather than a case statement, so an event type
  # nobody declared is a blocked row with a readable reason instead of a silent no-op.
  HANDLERS = {
    'invoice' => :export_invoice,
    'refund' => :export_refund,
    'dispute' => :export_dispute
  }.freeze

  def initialize(event, source: nil, accounting: nil)
    @event = event
    @profile = event.destination_profile
    @source = source || Odoo::StripeSource.new
    @accounting = accounting
  end

  # Returns the event. Safe to call on a row another worker has already taken: the claim is conditional.
  def call
    return @event unless claim!
    return block('destination_not_enabled') unless @profile.sync_enabled?

    handler = HANDLERS[@event.provider_object_type]
    return block("unhandled_object_type_#{@event.provider_object_type}") if handler.nil?

    attempt = begin_attempt
    finish(attempt, send(handler))
  rescue Odoo::Error => e
    record_failure(attempt, e)
  rescue Odoo::CustomerResolver::Conflict => e
    record_review(attempt, e.reason)
  rescue Odoo::StripeSource::NotConfigured
    block('stripe_not_configured')
  end

  private

  # One UPDATE with the state in its WHERE clause. Two workers racing on the same row: exactly one update
  # affects a row, and the loser returns without doing anything. No lock, no Redis, same mechanism as
  # BillingWebhookEvent's unique index -- the database decides.
  # rubocop:disable Rails/SkipsModelValidations -- the claim IS the atomicity. Loading the row, checking its
  # state and saving it would leave a window two workers can both pass through, and there is no validation on
  # this table that a state transition could violate.
  def claim!
    taken = Odoo::SyncEvent.where(id: @event.id, state: [:pending, :retrying])
                           .update_all(state: Odoo::SyncState::STATES[:processing], claimed_at: Time.current,
                                       attempts_count: @event.attempts_count + 1, updated_at: Time.current)
    @event.reload if taken.positive?
    taken.positive?
  end
  # rubocop:enable Rails/SkipsModelValidations

  def begin_attempt
    Odoo::SyncAttempt.create!(sync_event: @event, attempt_number: @event.attempts_count,
                              outcome: Odoo::SyncAttempt::UNKNOWN_OUTCOME, started_at: Time.current)
  end

  def accounting
    @accounting ||= Odoo::Accounting.new(@profile)
  end

  def export_invoice
    invoice = Odoo::InvoiceExport.new(@profile, source: @source, accounting: accounting).call(@event.provider_object_id)
    return invoice unless invoice.state == :synchronized && invoice.mapping&.posted?

    # The payment is a SEPARATE document with its own key, attempted in the same pass because the invoice it
    # pays is the thing we just confirmed. Its own failure does not undo the invoice.
    Odoo::PaymentExport.new(@profile, source: @source, accounting: accounting).call(@event.provider_object_id, invoice.mapping)
    invoice
  end

  # A refund needs the invoice document it credits. Without one there is nothing to reverse, which is a state
  # for a person rather than an error: it means the invoice has not been exported yet, or was blocked.
  def export_refund
    refund = @source.refund(@event.provider_object_id)
    invoice_mapping = invoice_mapping_for(refund.charge)
    return review('invoice_not_exported') if invoice_mapping.nil?

    Odoo::RefundExport.new(@profile, source: @source, accounting: accounting).call(refund.id, invoice_mapping)
  end

  # NOTHING IS WRITTEN TO ODOO FOR A DISPUTE. A chargeback's treatment -- a provision, a write-off, a bank fee,
  # or all three -- differs by jurisdiction and by the owner's own policy, so this records that one happened
  # and leaves the accounting to the person who knows which it is.
  def export_dispute
    review('dispute_requires_manual_accounting')
  end

  def invoice_mapping_for(charge_id)
    charge = @source.charge(charge_id)
    invoice_id = charge.invoice.is_a?(String) ? charge.invoice : charge.invoice&.id
    return nil if invoice_id.blank?

    @profile.document_mappings.invoices.find_by(provider_object_id: invoice_id, state: Odoo::SyncState::STATES[:synchronized])
  end

  # The exporter's own verdict decides the event's state, so the queue and the documents never disagree.
  def finish(attempt, result)
    outcome = result.respond_to?(:state) ? result.state : :synchronized
    attempt.update!(outcome: outcome == :synchronized ? Odoo::SyncAttempt::SUCCEEDED : Odoo::SyncAttempt::NEEDS_REVIEW,
                    duration_ms: elapsed(attempt))
    settle(outcome, result.respond_to?(:reason) ? result.reason : nil)
  end

  def record_failure(attempt, error)
    attempt&.update!(outcome: error.classification.to_s, error_class: error.class.name, error_code: error.code,
                     reason: Odoo::SyncAttempt.scrub(error.detail || error.reason), duration_ms: elapsed(attempt))
    signal(error)
    error.retryable? && !@event.attempts_exhausted? ? retry_later(error) : terminal(error)
  end

  def record_review(attempt, reason)
    attempt&.update!(outcome: Odoo::SyncAttempt::NEEDS_REVIEW, reason: reason, duration_ms: elapsed(attempt))
    settle(:needs_review, reason)
  end

  def retry_later(error)
    @event.update!(state: :retrying, run_after: @event.next_run_after, last_error_class: error.code,
                   claimed_at: nil)
    @event
  end

  def terminal(error)
    state = error.classification == Odoo::Error::NEEDS_REVIEW ? :needs_review : :failed
    @event.update!(state: state, last_error_class: error.code, claimed_at: nil, completed_at: Time.current)
    @event
  end

  def settle(outcome, reason)
    @event.update!(state: outcome, blocked_reason: outcome == :blocked ? reason : nil, claimed_at: nil,
                   completed_at: outcome == :synchronized ? Time.current : nil)
    @event
  end

  def block(reason)
    @event.update!(state: :blocked, blocked_reason: reason, claimed_at: nil)
    @event
  end

  def review(reason)
    Odoo::InvoiceExport::Result.new(state: :needs_review, reason: reason)
  end

  # Through Operations::SignalRecorder, which is the only writer of a signal and never raises into its caller:
  # observability must not be able to fail the accounting work it is observing.
  def signal(error)
    Operations::SignalRecorder.new(source: :accounting_sync, subject: nil)
                              .record(:sync_failed, severity: error.retryable? ? :warning : :critical,
                                                    detail: { error_code: error.code, provider: 'odoo' })
  end

  def elapsed(attempt)
    return nil if attempt&.started_at.blank?

    ((Time.current - attempt.started_at) * 1000).round
  end
end
