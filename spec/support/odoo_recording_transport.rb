# An Odoo transport that records what would have gone out and answers the way Odoo does.
#
# A SUPPORT FILE RATHER THAN A SPEC-LOCAL CLASS, for two reasons: a class defined inside a `describe` block
# leaks into the global namespace for every spec that runs after it, and more than one spec needs this one.
#
# Its answers are the real shapes: `create` returns a recordset coerced to an id list, `read` returns a row
# with many2ones as [id, "Display Name"], and `action_create_payments` returns an ir.actions.act_window dict
# with the payment in `res_id`. A looser double would pass examples that production fails.
class OdooRecordingTransport
  NAME = 'recording'.freeze

  attr_reader :calls

  def initialize(answers = {})
    @calls = []
    @answers = answers
  end

  def call(model:, method:, ids: [], named: {}, context: {})
    @calls << { model: model, method: method, ids: ids, named: named, context: context }
    @answers.fetch(method) { default_for(method) }
  end

  def call_for(method)
    @calls.find { |call| call[:method] == method }
  end

  private

  def default_for(method)
    case method
    when 'create' then [4242]
    when 'read' then [posted_move]
    when 'search_read' then [{ 'id' => 2, 'name' => 'USD' }]
    when 'action_create_payments' then { 'res_id' => 99, 'type' => 'ir.actions.act_window' }
    else false
    end
  end

  def posted_move
    { 'id' => 4242, 'state' => 'posted', 'name' => 'INV/2026/0007', 'payment_state' => 'not_paid',
      'company_id' => [3, 'Lynomia'], 'journal_id' => [11, 'Sales'] }
  end
end
