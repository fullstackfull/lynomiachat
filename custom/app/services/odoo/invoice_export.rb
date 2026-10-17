# One Stripe invoice, as an Odoo customer invoice (docs/odoo/02-architecture.md §5).
#
# THE SOURCE OF TRUTH IS THE STRIPE INVOICE. Not a BillingPlan price, not a subscription status. An active
# subscription is not evidence that money moved -- `Billing::SubscriptionSync` maps Stripe's `trialing` onto
# our `active`, and `Billing::AdminActions#grant_plan` writes `active` with no Stripe subscription at all -- so
# a document is created from an invoice Stripe issued and from nothing else.
#
# THE SEQUENCE, AND WHY IT IS IN THIS ORDER:
#
#   1. claim the document mapping    the unique index on the idempotency key decides whether this is ours to do
#   2. recover, if a previous attempt may have written    search Odoo by our stamp; adopt what is there
#   3. create the DRAFT              never a posted move: Odoo refuses to create one, and so do we
#   4. read it back and COMPARE TOTALS    the gate that keeps a wrong invoice from ever being posted
#   5. read its LINES and VERIFY THIS PROJECT'S ATTRIBUTION    the gate that keeps unattributed revenue out of
#                                    a company shared with sibling projects
#   6. post, only if the operator has enabled posting AND both gates passed
#
# STEP 4. This integration writes into somebody else's chart of accounts, with their fiscal positions, their
# tax mapping and their rounding. It cannot predict what Odoo will compute. So it doesn't try: it creates the
# draft, asks Odoo what the total came to, and compares that against Stripe's own total. A draft whose total
# does not match Stripe is left as a draft and marked for review. Nothing posts on a number this integration
# cannot account for.
#
# STEP 5, for the same reason one layer along. The destination is ONE legal company running SEVERAL unrelated
# projects, so a correctly-totalled invoice with no analytic distribution is this project's revenue dropped
# into a pool the owner cannot split. Sending the attribution is not evidence it landed: Odoo computes
# `analytic_distribution` where none was supplied, and an `account.analytic.distribution.model` rule in the
# destination database can replace the one we sent. So the journal items are read back and checked, and a
# draft whose attribution did not land -- or landed on another project's analytic account -- is left a draft
# for a person. See Odoo::Attribution.
#
# WHAT IS NOT EXPORTED, and each is a deliberate refusal rather than a gap:
#   * a zero-amount invoice. Stripe issues them for trials and 100%-discounted periods. There is no revenue to
#     record, so recording it would be noise at best; the mapping is kept, marked blocked with its reason, and
#     shown in the UI so an operator can see that it was seen.
#   * Stripe's own fees. They are on the balance transaction, not the invoice, and they are an expense rather
#     than negative revenue. Booking them automatically would misclassify them in the owner's ledger.
#   * anything belonging to a tenant's own shop. The commerce tables are not read by this integration at all.
class Odoo::InvoiceExport
  DOCUMENT_KIND = 'customer_invoice'.freeze
  PROVIDER_OBJECT_TYPE = 'invoice'.freeze

  Result = Struct.new(:mapping, :state, :reason, keyword_init: true)

  def initialize(profile, source: nil, accounting: nil)
    @profile = profile
    @source = source || Odoo::StripeSource.new
    @accounting = accounting || Odoo::Accounting.new(profile)
    @stamp = Odoo::SourceStamp.new(profile)
    @attribution = Odoo::Attribution.new(profile)
  end

  def call(stripe_invoice_id)
    invoice = @source.invoice(stripe_invoice_id)
    account = @source.account_for_customer(customer_id(invoice))
    return blocked(invoice, 'unknown_stripe_customer') if account.nil?
    return blocked(invoice, 'zero_amount_not_exported', account: account) if total_minor(invoice).zero?

    export(invoice, account)
  end

  private

  def export(invoice, account)
    customer = Odoo::CustomerResolver.new(@profile, accounting: @accounting).resolve!(account)
    mapping = claim(invoice, account, customer)
    return Result.new(mapping: mapping, state: :synchronized) if mapping.state_synchronized?

    move = existing_move(mapping) || create_move(invoice, customer, mapping)
    settle(mapping, invoice, move)
  rescue Odoo::CustomerResolver::Conflict => e
    review(claim(invoice, account, nil), e.reason)
  end

  # The idempotency record. `claim!` returns nil when the row is already there, in which case this is a retry
  # or a redelivery and the EXISTING row is what the rest of the method works on -- never a second document.
  def claim(invoice, account, customer)
    key = @stamp.idempotency_key(document_kind: DOCUMENT_KIND, provider_object_id: invoice.id)
    Odoo::DocumentMapping.claim!(
      destination_profile: @profile, customer_mapping: customer, account_id: account&.id,
      provider: 'stripe', provider_object_type: PROVIDER_OBJECT_TYPE, provider_object_id: invoice.id,
      document_kind: DOCUMENT_KIND, odoo_model: 'account.move',
      source_reference: @stamp.reference(kind: PROVIDER_OBJECT_TYPE, provider_object_id: invoice.id),
      idempotency_key: key, amount_minor: total_minor(invoice), currency: invoice.currency,
      occurred_at: Time.zone.at(invoice.created), state: :processing
    ) || Odoo::DocumentMapping.find_by!(idempotency_key: key)
  end

  # RECOVERY FROM A LOST ANSWER. A previous attempt may have created the move and died before recording its id,
  # which is the one case where repeating the write would invoice a customer twice. So before creating
  # anything, Odoo is asked whether it already holds a move carrying our stamp inside our scope. Finding one is
  # adopting our own earlier work, not adopting a stranger's record -- the stamp is ours and the scope is ours.
  def existing_move(mapping)
    # The stamp is passed, so a stored id that points at a move which is NOT ours -- a sibling project's
    # invoice in the same company and the same journal -- is a conflict rather than a document we adopt.
    return @accounting.read_move(mapping.odoo_record_id, reference: mapping.source_reference) if mapping.odoo_record_id.present?

    rows = @accounting.find_moves(reference: mapping.source_reference, move_type: 'out_invoice')
    raise Odoo::Error.new('CONFLICT', reason: 'stamp_matches_several_moves') if rows.length > 1

    rows.first
  end

  def create_move(invoice, customer, mapping)
    draft = Odoo::Accounting::Draft.new(
      partner_id: customer.odoo_partner_id, reference: mapping.source_reference,
      invoice_date: Time.zone.at(invoice.created).to_date.to_s, currency_id: @accounting.currency_id(invoice.currency),
      lines: lines_for(invoice)
    )
    @accounting.read_move(@accounting.create_invoice(draft), reference: mapping.source_reference)
  end

  # The gate. Odoo's computed total against Stripe's, then post only if they agree and the operator has
  # enabled posting. `may_post?` already requires the capability proof, so an operator cannot switch posting on
  # for a destination that has never accepted a write.
  def settle(mapping, invoice, move)
    mapping.update!(odoo_record_id: move['id'], odoo_state: move['state'], odoo_payment_state: move['payment_state'],
                    odoo_state_read_at: Time.current, **@attribution.mapping_values)
    return review(mapping, 'total_mismatch_with_stripe') unless totals_agree?(invoice, move)

    verdict = verify_attribution(mapping, move)
    return review(mapping, verdict.reason) unless verdict.ok?
    return synchronized(mapping, move) unless @profile.may_post? && move['state'] == 'draft'

    synchronized(mapping, @accounting.post_move(move['id']))
  end

  # Reads the move's journal items and checks this project's attribution against them. `attribution_verified_at`
  # is stamped only on a pass, so the partial index on unverified attribution lists exactly the documents that
  # reached Odoo without it.
  def verify_attribution(mapping, move)
    verdict = @attribution.verify(@accounting.read_move_lines(move['id']))
    mapping.update!(attribution_verified_at: verdict.ok? ? Time.current : nil)
    verdict
  end

  # One minor unit of tolerance, to absorb the difference between Stripe's arithmetic and Odoo's. Anything
  # larger is a disagreement about what the customer owes, and the only safe response is to stop.
  def totals_agree?(invoice, move)
    expected = Odoo::Money.to_major(total_minor(invoice), invoice.currency)
    actual = BigDecimal(move['amount_total'].to_s)
    (expected - actual).abs <= Odoo::Money.tolerance(invoice.currency)
  end

  # One Odoo line per Stripe invoice line, at the amount Stripe put on it. Quantity is Stripe's own, and the
  # unit price is derived from it so the two multiply back to Stripe's amount.
  #
  # `amount_excluding_tax` when Stripe provides it, because an Odoo line's price_unit is pre-tax and Odoo adds
  # tax itself. When Stripe charged tax that Odoo is not configured to compute, the totals will not agree and
  # the invoice stops at step 4 rather than posting short -- which is the behaviour the comparison exists for.
  def lines_for(invoice)
    Array(invoice.lines&.data).map do |line|
      quantity = [line.quantity.to_i, 1].max
      amount = Odoo::Money.to_major(line_amount_minor(line), invoice.currency)
      { name: line.description.presence || default_line_label(invoice), quantity: quantity,
        price_unit: (amount / quantity) }
    end.presence || [fallback_line(invoice)]
  end

  # An invoice with no readable line items still has a total, and a document for it is better than no document
  # -- the total comparison will confirm it either way.
  def fallback_line(invoice)
    { name: default_line_label(invoice), quantity: 1,
      price_unit: Odoo::Money.to_major(total_minor(invoice), invoice.currency) }
  end

  def default_line_label(invoice)
    "Lynomia Chat subscription #{invoice.number.presence || invoice.id}"
  end

  def line_amount_minor(line)
    value = line.respond_to?(:amount_excluding_tax) ? line.amount_excluding_tax : nil
    (value.presence || line.amount).to_i
  end

  def total_minor(invoice)
    invoice.total.to_i
  end

  def customer_id(invoice)
    invoice.customer.is_a?(String) ? invoice.customer : invoice.customer&.id
  end

  def blocked(invoice, reason, account: nil)
    mapping = claim(invoice, account, nil)
    mapping.update!(state: :blocked, needs_review_reason: reason)
    Result.new(mapping: mapping, state: :blocked, reason: reason)
  end

  def review(mapping, reason)
    mapping.update!(state: :needs_review, needs_review_reason: reason)
    Result.new(mapping: mapping, state: :needs_review, reason: reason)
  end

  def synchronized(mapping, move)
    mapping.update!(state: :synchronized, odoo_state: move['state'], odoo_payment_state: move['payment_state'],
                    odoo_document_reference: move['name'].presence, odoo_state_read_at: Time.current,
                    posted_at: move['state'] == 'posted' ? Time.current : mapping.posted_at,
                    last_synced_at: Time.current, needs_review_reason: nil, last_error_class: nil)
    Result.new(mapping: mapping, state: :synchronized)
  end
end
