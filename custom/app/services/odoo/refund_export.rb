# A Stripe refund, as an Odoo credit note (docs/odoo/02-architecture.md §5, docs/odoo/05-limitations.md).
#
# TWO DIFFERENT ODOO OPERATIONS, because Odoo stopped having one. Until Odoo 16 the `account.move.reversal`
# wizard carried a `refund_method` selection with a 'Partial Refund' option. Odoo 17 removed the field, and
# `reverse_moves` now reverses the WHOLE move -- the wizard has no amount anywhere in it. So:
#
#   FULL refund    -> account.move.reversal + reverse_moves. Odoo writes the credit note, links it to the
#                     original through `reversed_entry_id`, and names it "Reversal of: <invoice>".
#   PARTIAL refund -> an ordinary account.move with move_type 'out_refund' carrying only the credited amount,
#                     linked to the original with `reversed_entry_id` so Odoo's own UI shows the relationship.
#
# THE PARTIAL CASE IS NOT RECONCILED HERE, and that is a decision rather than an omission. Reconciling a
# partial credit note against an invoice's receivable line is what decides whether the invoice reads 'partial'
# or 'paid', and it needs a judgement about which journal items to match -- a judgement this integration
# cannot make correctly on behalf of a ledger it does not own. So the credit note is created and posted, and
# the mapping is handed to an operator with the reason saying exactly what is left to do.
#
# A DISPUTE IS NOT A REFUND and is not exported as one. A chargeback's accounting treatment differs by
# jurisdiction and by the owner's own policy -- a provision, a write-off, a bank fee, or all three -- so
# guessing one would misstate the ledger. A dispute is recorded for review and nothing is written to Odoo.
class Odoo::RefundExport
  DOCUMENT_KIND = 'credit_note'.freeze
  PROVIDER_OBJECT_TYPE = 'refund'.freeze

  Result = Struct.new(:mapping, :state, :reason, keyword_init: true)

  def initialize(profile, source: nil, accounting: nil)
    @profile = profile
    @source = source || Odoo::StripeSource.new
    @accounting = accounting || Odoo::Accounting.new(profile)
    @stamp = Odoo::SourceStamp.new(profile)
  end

  # `stripe_refund_id` keys the document, so each refund against one invoice is its own credit note: a customer
  # refunded twice gets two credit notes, which is what the ledger needs and what one key per refund gives.
  def call(stripe_refund_id, invoice_mapping)
    refund = @source.refund(stripe_refund_id)
    mapping = claim(refund, invoice_mapping)
    return Result.new(mapping: mapping, state: :synchronized) if mapping.state_synchronized?
    return blocked(mapping, 'invoice_not_posted') unless invoice_mapping.posted?
    return blocked(mapping, 'posting_disabled') unless @profile.may_post?

    issue(refund, invoice_mapping, mapping)
  end

  private

  def issue(refund, invoice_mapping, mapping)
    return adopt(mapping) if mapping.odoo_record_id.present?

    if full?(refund, invoice_mapping)
      full_reversal(refund, invoice_mapping, mapping)
    else
      partial_credit_note(refund, invoice_mapping, mapping)
    end
  end

  # Compared in MINOR UNITS against the amount this integration recorded for the invoice, not against a total
  # read from Odoo: the question is what Stripe refunded of what Stripe charged, and both halves of that come
  # from Stripe.
  def full?(refund, invoice_mapping)
    refund.amount.to_i >= invoice_mapping.amount_minor.to_i
  end

  def full_reversal(refund, invoice_mapping, mapping)
    credit_id = @accounting.reverse_move(move_id: invoice_mapping.odoo_record_id, date: refunded_on(refund).to_s,
                                         reason: mapping.source_reference)
    raise Odoo::Error.new('INVALID_RESPONSE', reason: 'no_reversal_created') if credit_id.blank?

    # NOT assumed to be posted: Odoo creates a reversal dated in the future with auto_post 'at_date', so the
    # state is read rather than asserted.
    settle(mapping, @accounting.read_move(credit_id), full: true)
  end

  def partial_credit_note(refund, invoice_mapping, mapping)
    draft = Odoo::Accounting::Draft.new(
      partner_id: invoice_mapping.customer_mapping&.odoo_partner_id, reference: mapping.source_reference,
      invoice_date: refunded_on(refund).to_s, currency_id: @accounting.currency_id(refund.currency),
      lines: [{ name: line_label(invoice_mapping), quantity: 1,
                price_unit: Odoo::Money.to_major(refund.amount, refund.currency) }]
    )
    credit_id = @accounting.create_partial_credit_note(draft, reversed_entry_id: invoice_mapping.odoo_record_id)
    posted = @accounting.post_move(credit_id)
    settle(mapping, posted, full: false)
  end

  def claim(refund, invoice_mapping)
    key = @stamp.idempotency_key(document_kind: DOCUMENT_KIND, provider_object_id: refund.id)
    Odoo::DocumentMapping.claim!(
      destination_profile: @profile, customer_mapping: invoice_mapping.customer_mapping,
      account_id: invoice_mapping.account_id, provider: 'stripe',
      provider_object_type: PROVIDER_OBJECT_TYPE, provider_object_id: refund.id,
      document_kind: DOCUMENT_KIND, odoo_model: 'account.move',
      source_reference: @stamp.reference(kind: PROVIDER_OBJECT_TYPE, provider_object_id: refund.id),
      idempotency_key: key, amount_minor: refund.amount.to_i, currency: refund.currency,
      occurred_at: refunded_on(refund), state: :processing
    ) || Odoo::DocumentMapping.find_by!(idempotency_key: key)
  end

  def adopt(mapping)
    settle(mapping, @accounting.read_move(mapping.odoo_record_id), full: nil)
  end

  # A full reversal is finished when Odoo says it is posted. A partial credit note is a document that exists
  # and is correct, with one step left that a person has to take in Odoo -- so it is `needs_review` rather than
  # `synchronized`, and the reason says what the step is.
  def settle(mapping, move, full:)
    mapping.update!(odoo_record_id: move['id'], odoo_state: move['state'],
                    odoo_document_reference: move['name'].presence, odoo_state_read_at: Time.current,
                    posted_at: move['state'] == 'posted' ? Time.current : nil, last_synced_at: Time.current,
                    last_error_class: nil, **settled_state(full))
    Result.new(mapping: mapping, state: mapping.state.to_sym, reason: mapping.needs_review_reason)
  end

  def settled_state(full)
    return { state: :synchronized, needs_review_reason: nil } unless full == false

    { state: :needs_review, needs_review_reason: 'partial_credit_note_awaiting_reconciliation' }
  end

  def line_label(invoice_mapping)
    "Refund of #{invoice_mapping.odoo_document_reference.presence || invoice_mapping.provider_object_id}"
  end

  def refunded_on(refund)
    Time.zone.at(refund.created)
  end

  def blocked(mapping, reason)
    mapping.update!(state: :blocked, needs_review_reason: reason)
    Result.new(mapping: mapping, state: :blocked, reason: reason)
  end
end
