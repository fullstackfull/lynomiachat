# Odoo's ORM, as this integration uses it (docs/odoo/03-adapter.md §2).
#
# ONE CALL VOCABULARY, TWO DIALECTS. Every operation below is expressed with NAMED arguments, because JSON-2
# cannot express a positional one. The legacy endpoint can express named arguments too, so one description
# serves both; the reverse would not be true, and a vocabulary that only the older transport could speak would
# have to be rewritten the day the customer upgrades.
#
# WHAT IT DELIBERATELY DOES NOT DO:
#   * no transaction. Odoo runs each external call in its own SQL transaction and documents that chaining
#     calls inside one is impossible, so nothing here pretends a create and a post are atomic.
#   * no retry. Repeating an accounting write is a decision that needs to know whether the write was
#     idempotent; that lives with Odoo::SyncEvent, not with a method called `create`.
#   * no private methods. Odoo refuses any method whose name begins with `_` over RPC, so `action_post`,
#     `action_create_payments` and `reverse_moves` are the real entry points -- never `_post`.
class Odoo::Client
  def initialize(profile, transport: nil)
    @profile = profile
    @transport = transport || build_transport
  end

  # Always pass `fields` explicitly. account.move overrides `read` and `search_read` to substitute its own
  # default field list when `fields` is omitted, so a bare read silently returns a different set.
  def search_read(model:, domain:, fields:, limit: nil, order: nil)
    named = { domain: domain, fields: fields, limit: limit, order: order }.compact
    Array(@transport.call(model: model, method: 'search_read', named: named))
  end

  def read(model:, ids:, fields:)
    Array(@transport.call(model: model, method: 'read', ids: Array(ids), named: { fields: fields }))
  end

  # Returns the new record's id. Odoo 17+ takes `vals_list`, and a recordset comes back from JSON-2 as its id
  # list while the legacy endpoint may answer with a bare integer, so both shapes are accepted.
  def create(model:, values:, context: {})
    one_id(@transport.call(model: model, method: 'create', named: { vals_list: [values] }, context: context))
  end

  def write(model:, ids:, values:, context: {})
    @transport.call(model: model, method: 'write', ids: Array(ids), named: { vals: values }, context: context)
  end

  # A method called on records, by its public name. The context matters more here than anywhere else: the
  # payment and reversal wizards read `active_model` and `active_ids` out of it rather than from arguments.
  def call_method(model:, method:, ids: [], named: {}, context: {})
    @transport.call(model: model, method: method, ids: Array(ids), named: named, context: context)
  end

  # The capability probe's instrument. `fields_get` is a read, costs one call, and answers questions no
  # version number can -- whether this server's account.move has the field the adapter is about to write.
  def fields_get(model:, fields: nil, attributes: %w[type required readonly selection])
    @transport.call(model: model, method: 'fields_get',
                    named: { allfields: fields, attributes: attributes }.compact)
  end

  def transport_name
    @transport.class::NAME
  end

  private

  # The stored transport, which Odoo::VersionProbe wrote when the operator tested the connection. Nothing
  # guesses here: a profile with no detected transport has not been tested, and running a sync against a
  # server whose dialect nobody established is how a credential ends up at the wrong endpoint.
  def build_transport
    case @profile.transport
    when Odoo::Transport::Json2::NAME then Odoo::Transport::Json2.new(@profile)
    when Odoo::Transport::JsonRpc::NAME then Odoo::Transport::JsonRpc.new(@profile)
    else raise Odoo::Error.new('NOT_CONFIGURED', reason: 'transport_not_detected')
    end
  end

  def one_id(result)
    id = result.is_a?(Array) ? result.first : result
    raise Odoo::Error.new('INVALID_RESPONSE', reason: 'no_id_returned') unless id.is_a?(Integer) && id.positive?

    id
  end
end
