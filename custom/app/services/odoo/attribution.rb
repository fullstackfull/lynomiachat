# Which project's revenue this is, inside one shared Odoo company (docs/odoo/08-project-attribution.md).
#
# THE PROBLEM. The destination Odoo holds ONE legal company, and several unrelated projects run inside it.
# So `company_id` answers "which legal entity" and nothing else: a sibling project's invoice sits in the same
# company, often in the same journal, sometimes against a partner with the same name. Company is where a
# document goes. It is not whose it is.
#
# TWO SEPARATE QUESTIONS, TWO SEPARATE MECHANISMS, and conflating them is how a shared ledger gets mixed:
#
#   "is this record OURS?"       -> the source stamp in Odoo's `ref` (Odoo::SourceStamp). Identity.
#   "whose REVENUE is this?"     -> this class. Attribution.
#
# ATTRIBUTION IS WHAT ODOO REPORTS ON. An analytic distribution on a revenue line is the mechanism Odoo
# provides for segregating a project's profit and loss inside a single company: posting a move generates
# `account.analytic.line` rows from the distribution, and those rows are what an analytic P&L reads. Without
# it, this project's revenue is indistinguishable from every sibling project's in the owner's own reports --
# which is the failure this file exists to prevent, and which no amount of `ref` stamping fixes, because
# Odoo's financial reports do not read `ref`.
#
# IT GOES ON REVENUE LINES ONLY, AND NOTHING IN ODOO WILL STOP US GETTING THAT WRONG. There is no constraint
# and no compute that clears a misplaced distribution: `_compute_analytic_distribution` assigns only for
# display_type 'product' lines and otherwise leaves whatever is stored alone. So this code is the only guard,
# and the consequence of failing is specific rather than cosmetic:
#
#   display_type 'product'       the revenue. THIS is what carries the distribution.
#   display_type 'payment_term'  the receivable. Odoo NEVER puts a distribution here itself -- the values
#                                `_compute_needed_terms` builds contain no analytic key at all -- and posting
#                                a receivable line that has one creates a real account.analytic.line with the
#                                OPPOSITE SIGN, silently cancelling the revenue line's attribution. So our
#                                account on a payment-term line is a verification failure.
#   display_type 'tax'           Odoo fills this one ITSELF, from the base line, whenever the tax carries the
#                                `analytic` flag ("Include in Analytic Cost"); otherwise it sets it to false.
#                                It is not ours to set and not ours to refuse: an externally written tax-line
#                                distribution does not even survive, because `analytic_distribution` is part
#                                of the key Odoo matches tax lines on, so a hand-edited tax line is deleted
#                                and re-added with Odoo's own value. A destination whose sales tax is flagged
#                                analytic therefore inflates this project's analytic total by the tax, which
#                                is the owner's tax configuration rather than a leak into another project --
#                                so it is REPORTED and not failed. See docs/odoo/05-limitations.md.
#
# This integration authors only `invoice_line_ids`, which Odoo computes as 'product' lines, and never passes
# an `account_id` that would convert one into a payment term. So the rule is kept structurally as well: there
# is no code path here that can reach a receivable, payable or tax line.
#
# SENT IS NOT STORED. Odoo computes `analytic_distribution` on lines where none was supplied, and an
# `account.analytic.distribution.model` rule in the destination database can fill or change one. So every
# document is READ BACK and checked (#verify), and a document whose attribution did not land the way it was
# sent is handed to a person rather than posted.
class Odoo::Attribution
  # Analytic distribution: Odoo's own mechanism, and the only one that segregates a project in Odoo's analytic
  # reporting. The default and the one to use.
  ANALYTIC = 'analytic'.freeze
  # A dedicated income account: the explicitly configured fallback for an Odoo that cannot do analytic
  # accounting. It segregates the revenue in the GENERAL ledger (its own P&L line) rather than analytically,
  # which is a real but narrower guarantee -- see docs/odoo/05-limitations.md. It exists so that an
  # unsupported server BLOCKS on a configured alternative instead of quietly writing unattributed revenue.
  INCOME_ACCOUNT = 'income_account'.freeze
  MODES = [ANALYTIC, INCOME_ACCOUNT].freeze

  # The whole line belongs to this project. Odoo stores the distribution as percentages per analytic account
  # and validates that a plan's share totals 100 for lines its applicability covers, so a project that owns
  # the revenue outright owns 100% of it.
  FULL_SHARE = 100.0
  # Odoo rounds analytic percentages to `analytic_precision` (2 by default), so a read-back can legitimately
  # differ from 100.0 in the last place.
  SHARE_TOLERANCE = BigDecimal('0.01')

  # What a read-back of a journal item has to tell us. `display_type` says which kind of line it is,
  # `account_id` is what the `income_account` mode sets, `analytic_distribution` is what the `analytic` mode
  # sets, and `balance` distinguishes a line that carries money from a note or a section header.
  LINE_FIELDS = %w[id display_type account_id analytic_distribution balance name].freeze

  # The lines that carry this project's income. Odoo 16 made `display_type` required on account.move.line with
  # 'product' as the default for invoice lines, so a revenue line always says so.
  REVENUE_DISPLAY_TYPE = 'product'.freeze
  # The line that must never carry this project's attribution. ONE entry, deliberately: the receivable, where
  # Odoo never puts one itself and where posting it would create an opposite-signed analytic line that cancels
  # the revenue. A TAX line is excluded from this list on purpose -- see the header: Odoo fills it from the
  # base line when the tax is flagged analytic, so failing on it would refuse to work with a destination whose
  # own tax configuration is doing exactly what Odoo intends.
  FORBIDDEN_DISPLAY_TYPES = %w[payment_term].freeze
  TAX_DISPLAY_TYPE = 'tax'.freeze

  # Why a document's attribution was not accepted. Each is a distinct accounting consequence, not a severity:
  # `foreign_analytic_account` means another project's books would be credited, while `missing` means nobody's
  # would.
  # `note` is an OBSERVATION rather than a verdict: something an operator should know that is not a reason to
  # refuse the document. Today there is one, the analytic tax line above.
  Result = Struct.new(:ok, :reason, :detail, :note, keyword_init: true) do
    def ok? = self[:ok] == true
  end

  OK = Result.new(ok: true).freeze

  def initialize(profile)
    @profile = profile
  end

  def mode = @profile.attribution_mode.presence || ANALYTIC

  def analytic? = mode == ANALYTIC

  # Is there enough configured to attribute anything at all? Asked by the profile's own `scope_complete?`, so
  # an unconfigured destination cannot reach a write.
  def configured?
    analytic? ? @profile.analytic_account_id.present? : @profile.income_account_id.present?
  end

  # The attribution added to every revenue line this integration authors. Merged into the line's values by
  # Odoo::Accounting, so there is one place that decides and no exporter that can forget.
  #
  # The analytic key is a STRING: `analytic_distribution` is a JSON column keyed by analytic account id, and a
  # JSON object's keys are strings whatever the transport did with the Ruby hash.
  def line_values
    return {} unless configured?
    return { 'analytic_distribution' => { @profile.analytic_account_id.to_s => FULL_SHARE } } if analytic?

    # `account_id` on a product line is legitimate and is how revenue is directed to a specific income
    # account. It is only dangerous when the account is receivable or payable, because Odoo's
    # _compute_display_type would then convert the line into a payment term -- which is why the capability
    # probe refuses to accept an income account whose `account_type` is not an income type.
    { 'account_id' => @profile.income_account_id }
  end

  # What this document was attributed to, recorded ON the document mapping. The profile is mutable; a mapping
  # that stored only "see the profile" would silently rewrite its own history the moment an operator chose a
  # different analytic account.
  def mapping_values
    { attribution_mode: mode, odoo_analytic_account_id: analytic? ? @profile.analytic_account_id : nil,
      odoo_income_account_id: analytic? ? nil : @profile.income_account_id }
  end

  # THE READ-BACK CHECK. Given the journal items Odoo actually holds for a move, did this project's
  # attribution land, and did it land only where it belongs?
  #
  # Three independent failures, each with its own consequence:
  #   * a line naming an analytic account that is not ours -> another project's reporting would be credited;
  #   * our account on a receivable or tax line            -> this project's analytic P&L would double-count;
  #   * no revenue line carrying ours                      -> the revenue is unattributed in the shared company.
  def verify(lines)
    rows = Array(lines)
    return Result.new(ok: false, reason: 'attribution_no_lines_read') if rows.empty?
    return verify_income_account(rows) unless analytic?

    misplaced(rows) || verify_analytic(rows)
  end

  private

  # Checked across EVERY line, including ones this integration did not author, because a distribution model in
  # the destination database can add one -- and an allocation that does NOT name this project is a share of
  # our revenue being credited to something else.
  def misplaced(rows)
    credited_elsewhere(rows) || on_the_receivable(rows)
  end

  # An allocation that does not name this project is a share of our revenue being credited to something else.
  def credited_elsewhere(rows)
    row = rows.find { |candidate| allocations_of(candidate).any? { |allocation| !ours?(allocation) } }
    return nil if row.nil?

    Result.new(ok: false, reason: 'attribution_foreign_analytic_account', detail: label(row))
  end

  # Our account on a payment-term line would post an opposite-signed analytic line that cancels the revenue.
  def on_the_receivable(rows)
    row = rows.find do |candidate|
      FORBIDDEN_DISPLAY_TYPES.include?(candidate['display_type']) &&
        allocations_of(candidate).any? { |allocation| ours?(allocation) }
    end
    return nil if row.nil?

    Result.new(ok: false, reason: 'attribution_on_receivable_line', detail: label(row))
  end

  # Odoo's own doing when the tax is flagged analytic, so not a failure -- but it means this project's
  # analytic total includes the tax, which an operator reading an analytic P&L needs to know.
  def tax_note(rows)
    return nil unless rows.any? { |row| row['display_type'] == TAX_DISPLAY_TYPE && allocations_of(row).any? }

    'tax_lines_carry_attribution'
  end

  def verify_analytic(rows)
    revenue = revenue_lines(rows)
    return Result.new(ok: false, reason: 'attribution_no_revenue_line') if revenue.empty?

    unattributed = revenue.reject { |row| full_share?(our_share(row)) }
    return Result.new(ok: true, note: tax_note(rows)) if unattributed.empty?

    reason = our_share(unattributed.first).positive? ? 'attribution_partial' : 'attribution_missing'
    Result.new(ok: false, reason: reason, detail: label(unattributed.first))
  end

  def verify_income_account(rows)
    revenue = revenue_lines(rows)
    return Result.new(ok: false, reason: 'attribution_no_revenue_line') if revenue.empty?

    wrong = revenue.reject { |row| Array(row['account_id']).first == @profile.income_account_id }
    return OK if wrong.empty?

    Result.new(ok: false, reason: 'attribution_income_account_not_applied', detail: label(wrong.first))
  end

  # A section header and a note are display_type 'line_section' / 'line_note' and carry no money, so they are
  # not revenue and are not expected to be attributed. Everything else that says 'product' is.
  def revenue_lines(rows)
    rows.select { |row| row['display_type'] == REVENUE_DISPLAY_TYPE }
  end

  # Odoo returns the JSON column as a hash keyed by analytic account id AS A STRING, or as `false` when it is
  # unset. One ENTRY is one allocation of a percentage of the line.
  #
  # A key may be a COMMA-JOINED list of ids ("41,88") from Odoo 17 on, and that is not a split: it is one
  # allocation of that percentage charged simultaneously to one account per analytic PLAN, producing a single
  # account.analytic.line with one column filled per plan. So an allocation naming this project alongside an
  # account in another plan is still wholly ours, while a SEPARATE entry naming only other accounts is a share
  # of our revenue going somewhere else. Reading them as allocations rather than as a flat id list is what
  # keeps those two apart. (Odoo 16 accepts single-id keys only; we never write a composite one.)
  def allocations_of(row)
    raw = row && row['analytic_distribution']
    return [] unless raw.is_a?(Hash)

    raw.map { |key, share| { ids: key.to_s.split(',').map(&:to_i), share: BigDecimal(share.to_s) } }
  end

  def ours?(allocation)
    allocation[:ids].include?(@profile.analytic_account_id)
  end

  # Everything on this line that reaches this project, across however many allocations Odoo ended up with.
  def our_share(row)
    allocations_of(row).select { |allocation| ours?(allocation) }.sum { |allocation| allocation[:share] }
  end

  def full_share?(share)
    (share - BigDecimal(FULL_SHARE.to_s)).abs <= SHARE_TOLERANCE
  end

  # Enough to find the line in Odoo, and nothing that could carry a customer's details into a log line or an
  # audit entry.
  def label(row)
    return nil if row.nil?

    "line_#{row['id']}"
  end
end
