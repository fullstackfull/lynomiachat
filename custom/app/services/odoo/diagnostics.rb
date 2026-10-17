# What this destination can actually do, established by asking it (docs/odoo/04-diagnostics.md).
#
# THE POINT OF THIS FILE is the brief's hardest requirement: "a successful login or Test Connection is NOT
# sufficient proof that invoice creation and posting work." It is not, and the reasons are specific. A login
# proves a key is valid. It does not prove the configured journal is a SALE journal, or that it belongs to the
# configured company, or that the API user may write to account.move, or that this server's chart of accounts
# and fiscal positions accept the line shape this adapter sends. Each of those is a separate question with its
# own answer, so each is its own probe and each is reported separately.
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

  def probes
    { 'model_shape' => -> { model_shape },
      'company' => -> { company },
      'sale_journal' => -> { journal(@profile.journal_id, [SALE_JOURNAL_TYPE]) },
      'payment_journal' => -> { journal(@profile.payment_journal_id, PAYMENT_JOURNAL_TYPES) },
      'analytic_account' => -> { analytic_account },
      'draft_create' => -> { draft_round_trip } }
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

  # Skipped rather than failed when none is configured: analytic accounting is not present in every Odoo
  # edition and version, so requiring one would make the integration unusable where there is nothing to pick.
  def analytic_account
    return { 'skipped' => true, 'reason' => 'not_configured' } if @profile.analytic_account_id.blank?

    row = one('account.analytic.account', [['id', '=', @profile.analytic_account_id]], %w[id name company_id])
    { 'ok' => true, 'name' => row['name'] }
  end

  # The one write, and its undoing. No partner: `partner_id` is not required to CREATE an account.move (Odoo
  # enforces it at posting time), so the probe does not have to invent a customer in somebody's database. One
  # zero-priced line, because a move with no line at all is refused by posting and this still proves the line
  # shape is accepted.
  def draft_round_trip
    draft = Odoo::Accounting::Draft.new(
      reference: Odoo::SourceStamp.new(@profile).reference(kind: 'probe', provider_object_id: SecureRandom.hex(6)),
      invoice_date: Date.current.to_s, currency_id: nil,
      lines: [{ name: PROBE_LINE_LABEL, quantity: 1, price_unit: 0.0 }]
    )
    accounting = Odoo::Accounting.new(@profile, client: client)
    move_id = accounting.create_invoice(draft)
    row = accounting.read_move(move_id)
    accounting.unlink_draft_move(move_id)
    { 'ok' => true, 'state' => row['state'], 'journal' => Array(row['journal_id']).last, 'removed' => true }
  end

  def one(model, domain, fields)
    row = client.search_read(model: model, domain: domain, fields: fields, limit: 1, context: Odoo::SourceStamp.new(@profile).call_context).first
    raise Odoo::Error.new('NOT_FOUND', reason: model.tr('.', '_')) if row.nil?

    row
  end

  def mismatch(reason, found)
    { 'ok' => false, 'error' => { 'code' => 'INVALID_REQUEST', 'reason' => reason }, 'found' => found }
  end

  # fields_get returns a selection as an array of [value, label] pairs.
  def selection_values(definition)
    Array(definition && definition['selection']).map { |pair| Array(pair).first }
  end
end
