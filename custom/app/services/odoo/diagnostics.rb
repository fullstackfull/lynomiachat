# What this destination can actually do, established by asking it (docs/odoo/04-diagnostics.md).
#
# THE POINT OF THIS FILE is the hardest requirement in the brief: "a successful login or Test Connection is
# NOT sufficient proof that invoice creation and posting work." It is not, and the reasons are specific. A
# login proves a key is valid. It does not prove the configured journal is a SALE journal, or that it belongs
# to the configured company, or that the API user may write to account.move, or that this server's chart of
# accounts and fiscal positions accept the line shape this adapter sends. Each of those is a separate question
# with its own answer, so each is its own probe and each is reported separately.
#
# AND IT PROVES ATTRIBUTION, which in a company shared with sibling projects is the probe that matters most.
# The destination holds ONE legal company running SEVERAL unrelated projects, so an invoice that posts
# perfectly but carries no analytic distribution has put this project's revenue somewhere the owner cannot
# tell apart from the others'. Two probes cover it:
#
#   `attribution_setup`  the cheap reads -- does account.move.line even HAVE analytic_distribution on this
#                        server, does the configured analytic account exist, is it usable by this company.
#   `attribution`        the verdict from the draft round trip: the attribution we SENT, read back off the
#                        journal items Odoo actually stored. It never reports `skipped`, because
#                        Odoo::DestinationProfile#capability_proven? requires it by name -- an Odoo that
#                        cannot attribute this project's revenue BLOCKS activation rather than quietly
#                        exporting unattributed revenue.
#
# ONE WRITE, AND IT IS UNDONE. The only honest proof that invoice creation works is to create an invoice, so
# the probe creates a DRAFT, reads it back to confirm which company and journal it landed in, and deletes it.
# A draft has no sequence number -- Odoo assigns the number when the move leaves draft -- so deleting one
# leaves no accounting trace and no gap in the customer's numbering. Nothing else here writes anything.
#
# POSTING IS NOT PROVEN AND IS NOT CLAIMED TO BE. Posting creates a permanently numbered document in somebody
# else's books; there is no way to probe it without doing that. So this reports posting as `unproven` and the
# Settings screen says so, which is why automatic posting is a separate switch that an operator turns on
# deliberately after reading that sentence.
class Odoo::Diagnostics
  # The fields whose presence and selections tell us which Odoo this is, more reliably than a version string:
  # `payment_state` gained a 'blocked' value in Odoo 18, so its selection IS the version branch, read from the
  # server instead of inferred.
  SHAPE_FIELDS = %w[move_type state payment_state ref journal_id company_id invoice_line_ids].freeze
  SALE_JOURNAL_TYPE = 'sale'.freeze
  PAYMENT_JOURNAL_TYPES = %w[bank cash credit].freeze
  PROBE_LINE_LABEL = 'Lynomia Chat connection probe -- safe to ignore, this draft is deleted immediately'.freeze
  # A NON-ZERO probe amount, so the round trip proves something about a line that carries money: Odoo stores an
  # analytic distribution on a zero line too, but a zero line exercises neither the tax computation nor the
  # revenue account, and attribution is only interesting on revenue. One unit of the company's currency, on a
  # draft that is deleted in the same probe.
  PROBE_LINE_AMOUNT = 1.0
  # The account types Odoo treats as income. The `income_account` attribution mode refuses anything else,
  # because a receivable or payable account on a product line makes Odoo's _compute_display_type convert the
  # line into a payment term -- the invoice would still post, and its revenue would have vanished.
  INCOME_ACCOUNT_TYPES = %w[income income_other].freeze

  def initialize(profile)
    @profile = profile
  end

  # Unauthenticated version detection, then one authenticated read. Returns a hash safe to store and render:
  # a boolean, a version string, a transport name, and on failure a code and a reason from our own vocabulary.
  # Never a credential, never Odoo's traceback.
  def test_connection
    probe = Odoo::VersionProbe.new(@profile).call
    return { 'ok' => false, 'stage' => 'version', 'error' => probe.error } unless probe.ok?

    @profile.update!(odoo_version: probe.version, odoo_version_info: probe.info, transport: probe.transport)
    authenticated_read
  rescue Odoo::Error => e
    { 'ok' => false, 'stage' => 'authenticate', 'error' => e.as_json.stringify_keys }
  end

  # The real thing. Returns { 'ok' =>, 'probes' => { name => result }, 'posting' => 'unproven' }, and `ok` is
  # true only when every probe that was not skipped passed.
  def probe_capability
    return { 'ok' => false, 'error' => { 'code' => 'NOT_CONFIGURED', 'reason' => 'scope_incomplete' } } unless @profile.scope_complete?

    # Ordered cheapest first and WRITE LAST, so a misconfigured journal is reported by the journal probe
    # rather than discovered by a failed write whose error would name the symptom instead of the cause.
    results = probes.transform_values { |probe| run(&probe) }

    { 'ok' => results.values.all? { |r| r['ok'] || r['skipped'] }, 'probes' => results, 'posting' => 'unproven' }
  end

  private

  # Ordered cheapest first and WRITE SECOND TO LAST, so a misconfigured journal or analytic account is
  # reported by its own probe rather than discovered by a failed write whose error would name the symptom
  # instead of the cause. `attribution` comes last because it is a verdict on the write, not another call.
  def probes
    { 'model_shape' => -> { model_shape },
      'company' => -> { company },
      'sale_journal' => -> { journal(@profile.journal_id, [SALE_JOURNAL_TYPE]) },
      'payment_journal' => -> { journal(@profile.payment_journal_id, PAYMENT_JOURNAL_TYPES) },
      'attribution_setup' => -> { attribution_setup },
      'draft_create' => -> { round_trip },
      Odoo::DestinationProfile::ATTRIBUTION_PROBE => -> { attribution_verdict } }
  end

  def client
    @client ||= Odoo::Client.new(@profile)
  end

  # Each probe is independent: one failing journal must not hide what the next probe would have said, because
  # an operator fixing a misconfiguration wants the whole list, not the first line of it.
  def run
    yield
  rescue Odoo::Error => e
    { 'ok' => false, 'error' => e.as_json.stringify_keys, 'detail' => e.detail }.compact
  end

  # The cheapest authenticated call there is: reading the field definitions of a model proves the credential
  # works and the user may see account.move, and writes nothing.
  def authenticated_read
    shape = client.fields_get(model: 'account.move', fields: %w[move_type])
    return { 'ok' => false, 'stage' => 'authenticate', 'error' => { 'code' => 'INVALID_RESPONSE', 'reason' => 'no_fields' } } unless shape.is_a?(Hash)

    { 'ok' => true, 'version' => @profile.odoo_version, 'transport' => @profile.transport }
  end

  def model_shape
    shape = client.fields_get(model: 'account.move', fields: SHAPE_FIELDS)
    missing = SHAPE_FIELDS - shape.keys
    return { 'ok' => false, 'error' => { 'code' => 'INVALID_REQUEST', 'reason' => 'fields_missing' }, 'missing' => missing } if missing.any?

    { 'ok' => true,
      'payment_states' => selection_values(shape['payment_state']),
      'move_types' => selection_values(shape['move_type']) }
  end

  def company
    row = one('res.company', [['id', '=', @profile.company_id]], %w[id name currency_id])
    { 'ok' => true, 'name' => row['name'], 'currency' => Array(row['currency_id']).last }
  end

  # A journal has to be the right TYPE and in the right COMPANY. The type matters because Odoo refuses to post
  # a customer invoice into a non-sale journal, and the company matters because the journal is what pins the
  # invoice to a company -- a journal in the wrong one would silently post Lynomia's revenue into another
  # business's books, which is the exact failure this whole integration is built to prevent.
  def journal(journal_id, allowed_types)
    row = one('account.journal', [['id', '=', journal_id]], %w[id name type code company_id])
    return mismatch('journal_type', row['type']) unless allowed_types.include?(row['type'])
    return mismatch('journal_company', Array(row['company_id']).last) unless Array(row['company_id']).first == @profile.company_id

    { 'ok' => true, 'name' => row['name'], 'code' => row['code'], 'type' => row['type'] }
  end

  # NEVER SKIPPED. Attribution is not optional in a shared company: without it this project's revenue is
  # indistinguishable from a sibling project's in the owner's own reports, which is the thing this integration
  # exists to prevent.
  def attribution_setup
    return not_configured('attribution_not_configured') unless @profile.attribution_configured?

    @profile.attribution.analytic? ? analytic_setup : income_account_setup
  end

  # Two separate questions, because they fail for different reasons and an operator fixes them differently:
  # the SERVER may not support analytic distribution at all, or the configured ACCOUNT may be wrong.
  #
  # An analytic account with `company_id` false is shared across every company and is usable here; one
  # belonging to a different company is not, and Odoo would refuse the posting rather than the write, which is
  # exactly the kind of late failure this probe exists to pull forward.
  def analytic_setup
    shape = client.fields_get(model: 'account.move.line', fields: %w[analytic_distribution])
    return not_configured('analytic_distribution_unsupported') unless shape.is_a?(Hash) && shape.key?('analytic_distribution')

    # `active_test: false` so an ARCHIVED account is FOUND and refused by name rather than reported as
    # missing. Archiving is the silent-drop case: the distribution stores perfectly well, and posting then
    # produces no analytic line at all -- the revenue reaches Odoo attributed to nothing.
    row = one('account.analytic.account', [['id', '=', @profile.analytic_account_id]],
              %w[id name company_id plan_id active], context_extra: { 'active_test' => false })
    unusable_analytic_account(row) || analytic_account_ok(row)
  end

  # `company_id` false means the analytic account is SHARED across every company and is usable here. An id
  # belonging to another company is not: Odoo's own _check_company_auto on account.analytic.line raises at
  # POSTING time, which is exactly the late failure this probe exists to pull forward.
  def unusable_analytic_account(row)
    return mismatch('analytic_account_archived', row['name']) unless row['active']

    company = Array(row['company_id']).first
    return nil if company.blank? || company == @profile.company_id

    mismatch('analytic_account_company', Array(row['company_id']).last)
  end

  def analytic_account_ok(row)
    { 'ok' => true, 'mode' => Odoo::Attribution::ANALYTIC, 'account' => row['name'],
      'plan_id' => Array(row['plan_id']).first, 'plan' => Array(row['plan_id']).last,
      'shared_across_companies' => Array(row['company_id']).first.blank?,
      'distribution_models' => distribution_model_count }
  end

  # HOW MANY RULES IN THIS COMPANY CAN CHANGE AN ATTRIBUTION WE DID NOT WRITE. An
  # `account.analytic.distribution.model` row matches on partner, partner category, account prefix and
  # company, and Odoo consults it whenever it computes `analytic_distribution` -- which includes every line of
  # a PAYMENT move, because a payment is not an invoice and the compute's guard therefore falls through.
  #
  # A COUNT, NOT A VERDICT. Matching Odoo's prefix semantics here would be guesswork, and a probe that refused
  # a destination because the owner has distribution models would refuse most real installations. Zero means
  # nothing can interfere; any other number tells an operator to read docs/odoo/05-limitations.md §17 and
  # check those rules against their receivable and revenue accounts.
  def distribution_model_count
    client.search_read(model: 'account.analytic.distribution.model', fields: %w[id],
                       domain: [['company_id', 'in', [false, @profile.company_id]]],
                       context: Odoo::SourceStamp.new(@profile).call_context).length
  rescue Odoo::Error
    # Not knowing is not a failure of attribution: the round trip below still proves what Odoo stored.
    nil
  end

  # The configured fallback. It has to be an INCOME account the configured company can use, and the type check
  # is the one that matters: a receivable or payable account would be accepted by `create` and then silently
  # turn every revenue line into a payment term.
  #
  # THE COMPANY IS CHECKED BY THE SEARCH, not by reading a company field. account.account carries `company_id`
  # up to Odoo 17 and `company_ids` from 18, so reading either by name breaks on half the versions this
  # adapter supports. `one` searches with `allowed_company_ids` in the context instead, which is Odoo's own
  # multi-company record rule: an account this company cannot use is not returned at all, and the probe
  # reports NOT_FOUND.
  def income_account_setup
    row = one('account.account', [['id', '=', @profile.income_account_id]], %w[id name code account_type])
    return mismatch('income_account_type', row['account_type']) unless INCOME_ACCOUNT_TYPES.include?(row['account_type'])

    { 'ok' => true, 'mode' => Odoo::Attribution::INCOME_ACCOUNT, 'account' => row['name'], 'code' => row['code'],
      'account_type' => row['account_type'] }
  end

  # THE VERDICT ON THE WRITE. It compares what Odoo stored on the draft's journal items against what this
  # project's attribution should be -- which catches the three things no configuration read can: a
  # distribution model in the destination database overwriting ours, our analytic account landing on the
  # receivable or the tax line, and a revenue line reaching Odoo with no attribution at all.
  def attribution_verdict
    draft = round_trip
    return { 'ok' => false, 'error' => { 'code' => 'NOT_CONFIGURED', 'reason' => 'draft_not_created' } } unless draft['ok']

    verdict = draft['attribution']
    return { 'ok' => true, 'mode' => @profile.attribution.mode } if verdict.is_a?(Hash) && verdict['ok']

    { 'ok' => false, 'error' => { 'code' => 'INVALID_REQUEST', 'reason' => verdict.to_h['reason'].presence || 'attribution_not_verified' },
      'found' => verdict.to_h['detail'] }.compact
  end

  # ONE WRITE, READ BY TWO PROBES. Memoised including its failure, so `attribution` reports on the same draft
  # rather than creating a second one -- and so a server that refuses the write is not written to twice.
  def round_trip
    return @round_trip if defined?(@round_trip)

    @round_trip = run { draft_round_trip }
  end

  # The one write, and its undoing. No partner: `partner_id` is not required to CREATE an account.move (Odoo
  # enforces it at posting time), so the probe does not have to invent a customer in somebody's database. One
  # zero-priced line, because a move with no line at all is refused by posting and this still proves the line
  # shape is accepted.
  def draft_round_trip
    reference = Odoo::SourceStamp.new(@profile).reference(kind: 'probe', provider_object_id: SecureRandom.hex(6))
    draft = Odoo::Accounting::Draft.new(
      reference: reference, invoice_date: Date.current.to_s, currency_id: nil,
      lines: [{ name: PROBE_LINE_LABEL, quantity: 1, price_unit: PROBE_LINE_AMOUNT }]
    )
    accounting = Odoo::Accounting.new(@profile, client: client)
    move_id = accounting.create_invoice(draft)
    # Read back by id AND by our own stamp: the stamp check is what proves the move we are looking at is the
    # one we just wrote rather than a sibling project's move with the same id in a different company.
    row = accounting.read_move(move_id, reference: reference)
    verdict = @profile.attribution.verify(accounting.read_move_lines(move_id))
    accounting.unlink_draft_move(move_id)
    { 'ok' => true, 'state' => row['state'], 'journal' => Array(row['journal_id']).last, 'removed' => true,
      'attribution' => { 'ok' => verdict.ok?, 'reason' => verdict.reason, 'detail' => verdict.detail }.compact }
  end

  def one(model, domain, fields, context_extra: {})
    context = Odoo::SourceStamp.new(@profile).call_context.merge(context_extra)
    row = client.search_read(model: model, domain: domain, fields: fields, limit: 1, context: context).first
    raise Odoo::Error.new('NOT_FOUND', reason: model.tr('.', '_')) if row.nil?

    row
  end

  def mismatch(reason, found)
    { 'ok' => false, 'error' => { 'code' => 'INVALID_REQUEST', 'reason' => reason }, 'found' => found }
  end

  def not_configured(reason)
    { 'ok' => false, 'error' => { 'code' => 'NOT_CONFIGURED', 'reason' => reason } }
  end

  # fields_get returns a selection as an array of [value, label] pairs.
  def selection_values(definition)
    Array(definition && definition['selection']).map { |pair| Array(pair).first }
  end
end
