# Odoo's invoice lifecycle, as Odoo actually implements it (docs/odoo/03-adapter.md §3).
#
# EVERY RULE BELOW CAME OUT OF ODOO'S OWN SOURCE, not from a general idea of how accounting APIs behave, and
# each one is a way this integration would otherwise be quietly wrong:
#
#   * `move_type` MUST be set. account.move.move_type defaults to 'entry', so an invoice created without it is
#     not an invoice -- it is a bare journal entry, and nobody would notice until an accountant did.
#   * A POSTED MOVE CANNOT BE CREATED. account.move.create raises UserError on any vals carrying
#     state: 'posted'. Draft then post is not a style choice, it is the only sequence the server allows.
#   * `name` IS NOT SET BY US. The journal sequence assigns the legal number when the move leaves draft, and
#     _compute_name will silently reset a name we pre-assigned if it does not match the move's date. A draft
#     invoice legitimately has no number.
#   * `account_id` IS NOT SET ON A PRODUCT LINE. account.move.line._compute_display_type turns a line into a
#     'payment_term' line if its account is receivable or payable -- so passing the wrong account silently
#     converts a product line into a payment term and the invoice totals change.
#   * x2many VALUES ARE LITERAL TRIPLES. Odoo's `Command` helpers are Python-only; its own source says "Via
#     RPC, it is impossible nor to use the functions nor the command constant names", so lines go as
#     [[0, 0, {...}]].
#   * EVERYTHING IS READ BACK AFTER POSTING. action_post returns false, assigns the sequence number, and can
#     MOVE THE MOVE'S DATE if it falls in a locked period. The only way to know what the document became is to
#     read it.
#   * `payment_state` IS NEVER WRITTEN. It is a stored computed field with no inverse, derived from
#     reconciliation rows. Odoo's ORM would most likely accept the write and then overwrite it on the next
#     recompute, which is worse than a refusal: the ledger would briefly claim to be paid and then stop.
#   * EVERY REVENUE LINE CARRIES THIS PROJECT'S ATTRIBUTION. The destination company hosts several unrelated
#     projects, so revenue written without an analytic distribution (or, in the configured fallback, without
#     the dedicated income account) is revenue the owner cannot tell apart from a sibling project's. The
#     attribution is merged in by Odoo::Attribution at the one place lines are built, so no exporter can
#     forget it. It goes on product lines ONLY -- never on the receivable or the tax, which Odoo authors.
#   * A RECORD IS OURS BY ITS STAMP, NEVER BY ITS COMPANY. In a shared company, company and journal say only
#     where a document lives. Every lookup therefore goes through Odoo::SourceStamp#ownership_domain, which
#     will not build a search without an exact stamp, and every read by id is checked the same way.
#
# NOTHING HERE IS ATOMIC WITH ANYTHING ELSE. Odoo runs each external call in its own SQL transaction and
# documents that chaining calls inside one is impossible. So a create that succeeds followed by a post that
# fails leaves a real draft invoice in the customer's Odoo, and the caller's job is to find it again by its
# stamp rather than to create a second one.
class Odoo::Accounting
  # What a read-back of a move asks for. Explicit because account.move overrides `read` and `search_read` to
  # substitute its own default field list when `fields` is omitted.
  # `reversed_entry_id` is read so a credit note Odoo authored can be tied back to OUR invoice exactly, rather
  # than trusted because it is in the right company.
  MOVE_FIELDS = %w[id name ref state payment_state move_type amount_total amount_residual currency_id date
                   invoice_date journal_id company_id partner_id reversed_entry_id].freeze
  PARTNER_FIELDS = %w[id name ref email vat company_id].freeze
  PAYMENT_FIELDS = %w[id name ref state amount date journal_id company_id].freeze

  # A search asks for two so "exactly one matched" can be distinguished from "more than one did". More than one
  # is never resolved by picking the first: it means our stamp is on two records, which is a disagreement a
  # person has to settle.
  MATCH_LIMIT = 2

  # One document to write, as a value rather than as seven keyword arguments. The Stripe side builds it and
  # this class writes it, which keeps the mapping decisions (what the lines say, which currency, which date)
  # in the service that reads Stripe and the Odoo decisions here.
  Draft = Struct.new(:partner_id, :reference, :invoice_date, :currency_id, :lines, :move_type, :extra,
                     keyword_init: true) do
    def move_type = self[:move_type].presence || 'out_invoice'
    def extra = self[:extra].presence || {}
  end

  def initialize(profile, client: nil)
    @profile = profile
    @client = client || Odoo::Client.new(profile)
    @stamp = Odoo::SourceStamp.new(profile)
    @attribution = Odoo::Attribution.new(profile)
  end

  # ---- partners

  # Scope AND an exact stamp, never the scope alone and never a name or an email -- the sibling projects in
  # this company have partners with the same names and the same billing emails as ours. Returns the matching
  # rows so the caller can tell none from one from several.
  def find_partners(reference)
    @client.search_read(model: 'res.partner', fields: PARTNER_FIELDS, limit: MATCH_LIMIT, context: @stamp.call_context,
                        domain: @stamp.ownership_domain(model: 'res.partner', reference: reference))
  end

  # `company_id` is set so the partner belongs to the configured legal entity rather than being shared across
  # every company in the database. It is NOT what keeps this partner apart from the sibling projects in the
  # same company -- nothing about a company could be, and `ref` is what does it. Two projects invoicing the
  # same real customer will therefore each hold their own partner record for it, which is duplication rather
  # than leakage and is recorded as a known limitation (docs/odoo/05-limitations.md).
  def create_partner(name:, reference:, email: nil, vat: nil)
    @client.create(model: 'res.partner', context: @stamp.call_context,
                   values: { 'name' => name, 'ref' => reference, 'email' => email, 'vat' => vat,
                             'company_id' => @profile.company_id, 'is_company' => true }.compact)
  end

  # ---- lookups

  # Odoo wants a res.currency ID, not a code. An INACTIVE currency cannot carry a posted move -- Odoo's own
  # posting validation refuses one -- so a currency the destination has not enabled is a configuration problem
  # reported as such, rather than a document created against a currency that can never be posted.
  def currency_id(code)
    row = @client.search_read(model: 'res.currency', fields: %w[id name], limit: 1,
                              domain: [['name', '=', code.to_s.upcase]]).first
    row&.fetch('id', nil) or raise Odoo::Error.new('NOT_CONFIGURED', reason: "currency_not_enabled_#{code}")
  end

  # ---- invoices

  def find_moves(reference:, move_type:)
    @client.search_read(model: 'account.move', fields: MOVE_FIELDS, limit: MATCH_LIMIT, context: @stamp.call_context,
                        domain: @stamp.ownership_domain(model: 'account.move', reference: reference) +
                                [['move_type', '=', move_type]])
  end

  # A DRAFT customer invoice. `draft.lines` are plain hashes; the x2many triples are built here so no caller
  # has to remember the shape. Returns the new move's id.
  def create_invoice(draft)
    values = {
      'move_type' => draft.move_type,
      'partner_id' => draft.partner_id,
      'journal_id' => @profile.journal_id,
      'currency_id' => draft.currency_id,
      'invoice_date' => draft.invoice_date,
      'ref' => draft.reference,
      'invoice_line_ids' => Array(draft.lines).map { |line| [0, 0, invoice_line(line)] }
    }.merge(draft.extra.stringify_keys)
    @client.create(model: 'account.move', values: values, context: @stamp.call_context)
  end

  # Posting. Returns the move as Odoo holds it AFTERWARDS, because that is the only place the legal number
  # lives and because posting can move the date into the next open period.
  #
  # `validate_analytic` IS PASSED, and it is the only way to get Odoo's own analytic validation. Odoo's
  # mandatory-100%-distribution check sits inside `if not self.env.context.get('validate_analytic')`, and the
  # ONLY caller that sets it is the web UI's Confirm button -- so `action_post` over the External API posts an
  # invoice that breaches a mandatory analytic plan SILENTLY. In a company shared with sibling projects that
  # is the worst available outcome: a permanently numbered document whose revenue nobody can attribute. With
  # the key set, a destination whose analytic plans demand more than this integration knows how to supply
  # refuses the posting instead, and the draft is left for a person.
  #
  # Odoo raises a RedirectWarning rather than a ValidationError when the validation covers more than one move,
  # which cannot happen here: posting is one move per call.
  def post_move(move_id)
    @client.call_method(model: 'account.move', method: 'action_post', ids: [move_id],
                        context: @stamp.call_context.merge('validate_analytic' => true))
    read_move(move_id)
  end

  # A READ BY ID IS NOT SCOPED BY ANYTHING. `search_read` carries the destination scope in its domain, but
  # `read` returns whatever that id is in any company the API user can see. So the row is checked before it is
  # believed, and in a company shared with sibling projects the check has two halves:
  #
  #   DESTINATION -- is it in the configured company and journal? A move elsewhere is not where we write.
  #   OWNERSHIP   -- does its `ref` equal the stamp we expect? A move in the right company and the right
  #                  journal may still be a SIBLING PROJECT'S move, so a caller that knows which stamp it is
  #                  looking for passes it and a mismatch is a conflict. Company alone proves nothing here.
  #
  # `reference:` is omitted only where our stamp is not the record's ref by construction -- a credit note Odoo
  # authored from our invoice gets Odoo's own "Reversal of: ..." ref -- and those callers assert ownership
  # another way (Odoo::RefundExport checks `reversed_entry_id` against our own move id).
  #
  # Odoo returns a many2one as [id, "Display Name"], hence the Array(...).first on both sides.
  def read_move(move_id, reference: nil)
    row = @client.read(model: 'account.move', ids: [move_id], fields: MOVE_FIELDS, context: @stamp.call_context).first
    raise Odoo::Error.new('RECORD_MISSING', reason: 'move_gone') if row.nil?
    raise Odoo::Error.new('CONFLICT', reason: 'move_outside_destination_scope') unless in_scope?(row)
    raise Odoo::Error.new('CONFLICT', reason: 'move_stamp_mismatch') if reference.present? && row['ref'] != reference

    row
  end

  # The move's journal items, which is where attribution lives: `analytic_distribution` and `account_id` are
  # per line, and account.move has no analytic field of its own. Read rather than assumed because Odoo
  # computes a distribution on lines that were sent without one, and an
  # `account.analytic.distribution.model` rule in the destination database can change the one we sent.
  def read_move_lines(move_id)
    # No `limit`: every line of the move is wanted, and Odoo::Client omits the argument entirely when it is
    # nil rather than sending a zero, whose meaning differs between Odoo's own call sites.
    @client.search_read(model: 'account.move.line', fields: Odoo::Attribution::LINE_FIELDS,
                        context: @stamp.call_context, domain: [['move_id', '=', move_id]])
  end

  # Writes this project's attribution onto lines Odoo authored. Used for ONE case: a credit note that
  # `reverse_moves` created without copying the source invoice's distribution. Confined to a DRAFT -- a posted
  # move's journal items are a legal record and are reversed, never edited -- and confined to the revenue
  # lines, so the receivable and the tax are untouched.
  def apply_attribution(line_ids)
    return if line_ids.blank?

    @client.write(model: 'account.move.line', ids: Array(line_ids), values: @attribution.line_values,
                  context: @stamp.call_context)
  end

  # A draft invoice can be deleted and leaves no accounting trace: it never had a sequence number, so there is
  # no gap. Used by the capability probe and by nothing else -- a POSTED document is never unlinked by this
  # integration, because reversing it is the accounting answer and deleting it is not.
  def unlink_draft_move(move_id)
    @client.call_method(model: 'account.move', method: 'unlink', ids: [move_id], context: @stamp.call_context)
  end

  # ---- payments

  # Through account.payment.register, the transient wizard Odoo intends for this, instantiated with the
  # context it reads its target out of -- `active_model` and `active_ids` are not arguments, they are context,
  # and default_get raises if they name anything but account.move or account.move.line.
  #
  # `amount` is passed explicitly because the wizard's own default is the full residual: a partial payment is
  # expressed by overriding it, and the field is store+readonly=false precisely so that it can be.
  #
  # Returns the created payment's id. `dont_redirect_to_payments` is deliberately NOT passed: with it,
  # action_create_payments answers `true` and the payment's id is lost, and an accounting document we cannot
  # name is one we cannot reconcile later.
  def register_payment(move_id:, amount:, payment_date:, memo: nil)
    wizard_id = @client.create(
      model: 'account.payment.register',
      values: { 'payment_date' => payment_date, 'amount' => amount, 'journal_id' => @profile.payment_journal_id,
                'communication' => memo }.compact,
      context: wizard_context(move_id)
    )
    action = @client.call_method(model: 'account.payment.register', method: 'action_create_payments',
                                 ids: [wizard_id], context: wizard_context(move_id))
    payment_id_from(action)
  end

  # Checked against the destination for the same reason as a move: the id comes off a stored mapping, and a
  # payment in another company or another journal is not the payment this integration registered.
  def read_payment(payment_id)
    row = @client.read(model: 'account.payment', ids: [payment_id], fields: PAYMENT_FIELDS,
                       context: @stamp.call_context).first
    return nil if row.nil?
    raise Odoo::Error.new('CONFLICT', reason: 'payment_outside_destination_scope') unless payment_in_scope?(row)

    row
  end

  # ---- credit notes

  # A FULL reversal, through account.move.reversal. Returns the created credit note's id, read off the
  # wizard's own `new_move_ids` rather than parsed out of the ir.actions.act_window dict reverse_moves
  # returns -- the wizard stores the result on itself, which is a field rather than a UI payload.
  #
  # The reversal is NOT necessarily posted when this returns: a reversal dated in the future is created with
  # auto_post 'at_date'. The caller reads its state rather than assuming.
  def reverse_move(move_id:, date:, reason: nil)
    wizard_id = @client.create(model: 'account.move.reversal', context: wizard_context(move_id),
                               values: { 'date' => date, 'reason' => reason, 'journal_id' => @profile.journal_id }.compact)
    @client.call_method(model: 'account.move.reversal', method: 'reverse_moves', ids: [wizard_id],
                        context: wizard_context(move_id))
    row = @client.read(model: 'account.move.reversal', ids: [wizard_id], fields: %w[new_move_ids]).first
    Array(row && row['new_move_ids']).first
  end

  # A PARTIAL refund, which account.move.reversal cannot express: since Odoo 17 the wizard lost its
  # `refund_method` field and reverse_moves reverses the whole move, with no amount anywhere in it. So a
  # partial credit note is an ordinary out_refund move carrying only the credited amount, linked to the
  # original through `reversed_entry_id` so Odoo's own UI shows the relationship.
  #
  # IT IS NOT RECONCILED HERE, and that is deliberate rather than unfinished. Reconciling a partial credit
  # note against an invoice's receivable line is what decides whether the invoice reads 'partial' or 'paid',
  # and a wrong guess silently misstates a ledger this integration does not own. The document is created and
  # posted; the mapping is then put to an operator to reconcile in Odoo. See docs/odoo/05-limitations.md.
  def create_partial_credit_note(draft, reversed_entry_id:)
    credit = draft.dup
    credit.move_type = 'out_refund'
    credit.extra = draft.extra.merge('reversed_entry_id' => reversed_entry_id)
    create_invoice(credit)
  end

  private

  # THE ONE PLACE A REVENUE LINE IS BUILT, which is why the project attribution is merged in here: every
  # document this integration creates -- invoice, partial credit note, capability probe -- goes through it, so
  # there is no exporter that could write an unattributed line.
  #
  # A receivable or payable `account_id` is never passed, because Odoo's _compute_display_type would convert
  # the line into a payment term. The `income_account` attribution mode does pass an `account_id`, which is
  # legitimate for a product line and is why the capability probe refuses an account whose type is not income.
  # `product_id` is included only when the profile names a default product, because a product this Odoo does
  # not have would fail the whole invoice.
  def invoice_line(line)
    { 'name' => line[:name], 'quantity' => line.fetch(:quantity, 1), 'price_unit' => line[:price_unit],
      'product_id' => @profile.default_product_id }.compact.merge(@attribution.line_values)
  end

  # Where we write, not whose it is -- ownership is the stamp. Both journals are accepted because a payment
  # lands in the payment journal while the invoice it pays lands in the sale journal.
  def in_scope?(row)
    Array(row['company_id']).first == @profile.company_id &&
      [@profile.journal_id, @profile.payment_journal_id].include?(Array(row['journal_id']).first)
  end

  def payment_in_scope?(row)
    Array(row['company_id']).first == @profile.company_id &&
      Array(row['journal_id']).first == @profile.payment_journal_id
  end

  def wizard_context(move_id)
    @stamp.call_context.merge('active_model' => 'account.move', 'active_ids' => [move_id], 'active_id' => move_id)
  end

  # action_create_payments answers with an ir.actions.act_window dict: `res_id` for one payment, and a domain
  # of [('id','in',ids)] for several. We register one payment per call, so `res_id` is the answer; the domain
  # branch is read anyway rather than assumed away, because a wizard that grouped payments would use it.
  def payment_id_from(action)
    return action['res_id'] if action.is_a?(Hash) && action['res_id'].present?

    domain = action.is_a?(Hash) ? Array(action['domain']) : []
    ids = domain.find { |condition| Array(condition).first == 'id' }&.last
    Array(ids).first or raise Odoo::Error.new('INVALID_RESPONSE', reason: 'no_payment_id')
  end
end
