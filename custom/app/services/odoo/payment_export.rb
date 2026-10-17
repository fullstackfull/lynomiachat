# The money that actually arrived, registered against the Odoo invoice (docs/odoo/02-architecture.md §5).
#
# KEYED ON THE INVOICE, NOT ON THE CHARGE, and deliberately. Stripe has moved the link between an invoice and
# its payment more than once -- `payment_intent`, then `payments` -- so a design that reaches for whichever
# field this API version happens to expose is a design that breaks on an upgrade nobody initiated. What does
# not move is the invoice's own `amount_paid` and the invoice's own id, so the payment document is keyed on
# `payment:in_123` and its amount comes from `amount_paid`. A redelivery, a retry and the second
# `invoice.paid` after a failed first attempt all land on the same key and therefore on the same document.
#
# IT NEVER WRITES `payment_state`. Odoo computes that field from reconciliation rows and offers no inverse for
# it; a write would most likely be accepted and then silently overwritten at the next recompute, so the ledger
# would claim to be paid and then stop claiming it. The payment is registered through
# `account.payment.register`, which is what Odoo intends, and the resulting state is READ rather than asserted.
#
# IT CARRIES NO ANALYTIC ATTRIBUTION, and that is correct rather than an omission. A customer payment's
# journal items are the RECEIVABLE and the bank or outstanding-receipts account: the customer's debt being
# settled and the cash arriving. Neither is this project's income -- the income was recognised on the invoice,
# which is where the analytic distribution sits. Attributing the receivable as well would book the same money
# into the project's analytic accounts twice. See Odoo::Attribution.
#
# A PARTIAL PAYMENT IS NOT A PROBLEM. `amount_paid` below the invoice total is passed through as the amount,
# and Odoo's own computation reports `partial`. Nothing here rounds that up to paid.
class Odoo::PaymentExport
  DOCUMENT_KIND = 'payment'.freeze
  PROVIDER_OBJECT_TYPE = 'charge'.freeze

  Result = Struct.new(:mapping, :state, :reason, keyword_init: true)

  def initialize(profile, source: nil, accounting: nil)
    @profile = profile
    @source = source || Odoo::StripeSource.new
    @accounting = accounting || Odoo::Accounting.new(profile)
    @stamp = Odoo::SourceStamp.new(profile)
  end

  # `invoice_mapping` is the already-synchronized customer invoice. There is nothing to pay against without
  # one, which is why the runner exports the invoice first and only then calls this.
  def call(stripe_invoice_id, invoice_mapping)
    invoice = @source.invoice(stripe_invoice_id)
    paid_minor = invoice.amount_paid.to_i
    return skipped('nothing_paid') if paid_minor.zero?
    return blocked(invoice, invoice_mapping, 'invoice_not_posted') unless invoice_mapping.posted?
    return blocked(invoice, invoice_mapping, 'payment_registration_disabled') unless @profile.may_register_payments?

    register(invoice, invoice_mapping, paid_minor)
  end

  private

  def register(invoice, invoice_mapping, paid_minor)
    mapping = claim(invoice, invoice_mapping, paid_minor)
    return amount_changed(mapping, paid_minor) if mapping.state_synchronized? && mapping.amount_minor != paid_minor
    return Result.new(mapping: mapping, state: :synchronized) if mapping.state_synchronized?
    # A previous attempt got as far as recording the id; read it back rather than registering a second one.
    return settle(mapping, mapping.odoo_record_id, invoice_mapping) if mapping.odoo_record_id.present?
    return review(mapping, 'payment_may_already_exist') if settled?(invoice_mapping)

    payment_id = @accounting.register_payment(
      move_id: invoice_mapping.odoo_record_id, amount: Odoo::Money.to_major(paid_minor, invoice.currency),
      payment_date: paid_at(invoice).to_s, memo: invoice_mapping.source_reference
    )
    settle(mapping, payment_id, invoice_mapping)
  end

  # THE UNKNOWN-OUTCOME GUARD. An attempt may have registered the payment and then died before recording its
  # id, and registering a second one would take the customer's money twice in the owner's ledger. So the
  # invoice itself is asked: Odoo computes `payment_state` from its reconciliation rows, so an invoice that
  # already reads paid, in payment or partial has something reconciled against it. Rather than guess whether
  # that something is ours, the document goes to a person -- one confirmation is cheaper than one double
  # payment in a real ledger.
  def settled?(invoice_mapping)
    move = @accounting.read_move(invoice_mapping.odoo_record_id, reference: invoice_mapping.source_reference)
    %w[paid in_payment partial].include?(move['payment_state'])
  end

  # Stripe reported a different amount paid than the one this document was created for. The document is keyed
  # on the invoice, so a second partial payment against the same invoice arrives on the same key -- which is
  # correct for a redelivery and wrong for genuinely more money, and only a person can tell which. Honest
  # about it rather than silently under-recording. See docs/odoo/05-limitations.md.
  def amount_changed(mapping, paid_minor)
    review(mapping, "amount_paid_changed_from_#{mapping.amount_minor}_to_#{paid_minor}")
  end

  def review(mapping, reason)
    mapping.update!(state: :needs_review, needs_review_reason: reason)
    Result.new(mapping: mapping, state: :needs_review, reason: reason)
  end

  def claim(invoice, invoice_mapping, paid_minor)
    key = @stamp.idempotency_key(document_kind: DOCUMENT_KIND, provider_object_id: invoice.id)
    Odoo::DocumentMapping.claim!(
      destination_profile: @profile, customer_mapping: invoice_mapping.customer_mapping,
      account_id: invoice_mapping.account_id, provider: 'stripe',
      provider_object_type: PROVIDER_OBJECT_TYPE, provider_object_id: invoice.id,
      document_kind: DOCUMENT_KIND, odoo_model: 'account.payment',
      source_reference: @stamp.reference(kind: DOCUMENT_KIND, provider_object_id: invoice.id),
      idempotency_key: key, amount_minor: paid_minor, currency: invoice.currency,
      occurred_at: paid_at(invoice), state: :processing
    ) || Odoo::DocumentMapping.find_by!(idempotency_key: key)
  end

  # A previous attempt recorded the payment id and then failed before marking the row. Reading the payment back
  # is how we find out what it became, rather than registering a second one.
  def settle(mapping, payment_id, invoice_mapping)
    payment = @accounting.read_payment(payment_id) || {}
    mapping.update!(odoo_record_id: payment_id, odoo_document_reference: payment['name'].presence,
                    state: :synchronized, last_synced_at: Time.current, odoo_state_read_at: Time.current,
                    needs_review_reason: nil, last_error_class: nil)
    refresh_invoice_payment_state(invoice_mapping)
    Result.new(mapping: mapping, state: :synchronized)
  end

  # The invoice's payment status, read back from Odoo now that something has been reconciled against it. This
  # is the only way this integration ever learns that an invoice is paid: by asking.
  def refresh_invoice_payment_state(invoice_mapping)
    move = @accounting.read_move(invoice_mapping.odoo_record_id, reference: invoice_mapping.source_reference)
    invoice_mapping.update!(odoo_payment_state: move['payment_state'], odoo_state: move['state'],
                            odoo_state_read_at: Time.current)
  rescue Odoo::Error => e
    # A failed read-back does not undo a registered payment, so it must not fail the document either. The
    # invoice's displayed payment state is simply one refresh out of date until the next sync touches it.
    Rails.logger.warn("[Odoo] could not refresh payment state for mapping #{invoice_mapping.id}: #{e.code}")
  end

  # Stripe's own paid-at, not ours. An accounting document belongs to the period the money moved in, which is
  # not the period a worker happened to run in.
  def paid_at(invoice)
    stamp = invoice.status_transitions&.paid_at
    stamp.present? ? Time.zone.at(stamp) : Time.zone.at(invoice.created)
  end

  def skipped(reason)
    Result.new(state: :blocked, reason: reason)
  end

  def blocked(invoice, invoice_mapping, reason)
    mapping = claim(invoice, invoice_mapping, invoice.amount_paid.to_i)
    mapping.update!(state: :blocked, needs_review_reason: reason)
    Result.new(mapping: mapping, state: :blocked, reason: reason)
  end
end
