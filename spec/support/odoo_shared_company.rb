# A stand-in for ONE Odoo company shared by several unrelated projects
# (spec/security/odoo_project_isolation_spec.rb).
#
# IT IS DELIBERATELY PERMISSIVE. It is not a mock of this integration's own calls -- it is a fake SERVER, and
# it answers a `search_read` by applying the domain to a table holding every project's rows, the way the real
# Odoo does. Odoo offers no record-level isolation between projects inside one company: the only record rule
# on an analytic account is company-based, and `company_id` on one is not even required. So a domain that
# would match a sibling project's row on the real server matches one here, and anything this integration leaks
# leaks in the spec.
#
# It implements the subset of Odoo::Client that Odoo::Accounting uses, and records every call so an example
# can assert on the PAYLOAD rather than on the fact that a stub was reached.
class OdooSharedCompany
  attr_reader :calls, :rows

  def initialize(rows)
    @rows = rows
    @calls = []
    @next_id = rows.filter_map { |row| row['id'] }.max.to_i + 1
  end

  def search_read(model:, domain:, fields:, limit: nil, context: {})
    record(method: 'search_read', model: model, domain: domain, context: context)
    matched = @rows.select { |row| row['_model'] == model && matches?(row, domain) }
    matched = matched.first(limit) if limit
    matched.map { |row| project(row, fields) }
  end

  def read(model:, ids:, fields:, context: {})
    record(method: 'read', model: model, ids: Array(ids), context: context)
    @rows.select { |row| row['_model'] == model && Array(ids).include?(row['id']) }
         .map { |row| project(row, fields) }
  end

  def create(model:, values:, context: {})
    record(method: 'create', model: model, values: values, context: context)
    id = @next_id
    @next_id += 1
    @rows << values.merge('_model' => model, 'id' => id)
    id
  end

  def write(model:, ids:, values:, context: {})
    record(method: 'write', model: model, ids: Array(ids), values: values, context: context)
    true
  end

  def call_method(model:, method:, ids: [], named: {}, context: {})
    record(method: method, model: model, ids: Array(ids), named: named, context: context)
    true
  end

  # The one field the attribution probe asks about.
  def fields_get(model:, **)
    record(method: 'fields_get', model: model, context: {})
    { 'analytic_distribution' => { 'type' => 'json' } }
  end

  def transport_name = 'json2'

  # Every payload this integration sent, as JSON, for the examples that assert something was NEVER sent.
  def payloads
    @calls.filter_map { |call| call[:values] }.to_json
  end

  private

  # Odoo returns ONLY the fields you asked for, plus `id`. Honoured here so a spec cannot accidentally rely on
  # a field this integration never requested -- which would hide a missing entry in MOVE_FIELDS or
  # Odoo::Attribution::LINE_FIELDS until a real server returned the shorter row.
  def project(row, fields)
    row.except('_model').slice('id', *Array(fields))
  end

  def record(attributes)
    @calls << attributes
  end

  # Enough of Odoo's domain semantics for the clauses this integration actually sends: `=` and `in`. A many2one
  # reads back as [id, label], so the comparison is against the id.
  def matches?(row, domain)
    Array(domain).all? do |field, operator, value|
      actual = row[field]
      actual = Array(actual).first if actual.is_a?(Array)
      operator == 'in' ? Array(value).include?(actual) : actual == value
    end
  end
end
