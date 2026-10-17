# Odoo's long-standing JSON-RPC endpoint (docs/odoo/03-adapter.md §1).
#
# `POST /jsonrpc` with a JSON-RPC 2.0 envelope. Present on every Odoo from 8 onwards, which is why it is this
# integration's floor, and ALSO the endpoint Odoo's own 19.0 documentation schedules for removal in Odoo 22
# (autumn 2028) and Online 21.1 (winter 2027). So it is the fallback, not the preference.
#
# WHY NOT XML-RPC. Odoo's examples use `/xmlrpc/2`, but `xmlrpc` is not in this bundle and `require` of it
# fails (docs/odoo/00-discovery.md §9). `/jsonrpc` exposes the same `common` and `object` services over JSON,
# so there is nothing to gain from adding a gem to speak XML at a server that already speaks JSON.
#
# AUTHENTICATION IS TWO STEPS HERE, unlike JSON-2. `common.authenticate(db, login, key, {})` returns a numeric
# uid, and every subsequent `object.execute_kw` repeats the database, the uid and the key. An API key works in
# place of a password from Odoo 14 onwards.
#
# A BUSINESS REFUSAL ARRIVES AS HTTP 200. JSON-RPC puts the failure in the body's `error` object, so a 200 is
# not success and this class never treats it as one.
class Odoo::Transport::JsonRpc
  PATH = '/jsonrpc'.freeze
  NAME = 'jsonrpc'.freeze

  # Odoo exception class names, as they arrive in error.data.name. Mapped to our codes so the caller's retry
  # decision is made from a vocabulary we own rather than from Python class names.
  EXCEPTIONS = {
    'odoo.exceptions.AccessDenied' => 'AUTH_INVALID',
    'odoo.exceptions.AccessError' => 'PERMISSION_DENIED',
    'odoo.exceptions.UserError' => 'BUSINESS_RULE',
    'odoo.exceptions.ValidationError' => 'BUSINESS_RULE',
    'odoo.exceptions.RedirectWarning' => 'BUSINESS_RULE',
    # The record we asked about is not there any more. Somebody deleted it in Odoo, which is a disagreement
    # about reality rather than a bug, so it goes to a human.
    'odoo.exceptions.MissingError' => 'RECORD_MISSING',
    'psycopg2.errors.SerializationFailure' => 'SERVER_ERROR',
    'psycopg2.extensions.TransactionRollbackError' => 'SERVER_ERROR'
  }.freeze

  def initialize(profile, http: nil)
    @profile = profile
    @http = http || Odoo::Http.new(base_url: profile.base_url, log_tag: NAME)
  end

  # Unauthenticated, and deliberately so: the transport must be chosen from the server's version BEFORE any
  # credential is sent, so a wrong-dialect call never carries an API key.
  def version
    rpc(service: 'common', method: 'version', args: [])
  end

  # Returns the uid. Memoized per instance because `execute_kw` needs it on every call and a second
  # authenticate per document would double the request count for no information.
  def uid
    @uid ||= begin
      result = rpc(service: 'common', method: 'authenticate', args: [@profile.database, @profile.username, api_key, {}])
      # Odoo answers a bad credential with `false` rather than an error object, so the falsy answer IS the
      # failure and must not be allowed to become a uid of `false` in the next call's args.
      raise Odoo::Error.new('AUTH_INVALID', reason: 'rejected') unless result.is_a?(Integer) && result.positive?

      result
    end
  end

  # `ids` becomes execute_kw's first positional argument, which is how Odoo forms the recordset for a method
  # called on records. Everything else is passed by NAME, so one call description serves both transports --
  # JSON-2 cannot take positional arguments at all.
  def call(model:, method:, ids: [], named: {}, context: {})
    args = ids.present? ? [Array(ids)] : []
    kwargs = named.merge('context' => merged_context(context))
    rpc(service: 'object', method: 'execute_kw', args: [@profile.database, uid, api_key, model, method, args, kwargs])
  end

  private

  def api_key
    @profile.api_key.presence or raise Odoo::Error.new('NOT_CONFIGURED', reason: 'api_key_missing')
  end

  def merged_context(context)
    Odoo::SourceStamp.new(@profile).call_context.merge(context.to_h.stringify_keys)
  end

  def rpc(service:, method:, args:)
    body = { jsonrpc: '2.0', method: 'call', id: SecureRandom.uuid,
             params: { service: service, method: method, args: args } }
    status, parsed = @http.post_json(PATH, body)
    interpret(status, parsed)
  end

  def interpret(status, parsed)
    raise http_error(status) unless status == 200
    raise Odoo::Error.new('INVALID_RESPONSE', reason: 'not_json_rpc') unless parsed.is_a?(Hash)
    raise rpc_error(parsed['error']) if parsed['error'].present?

    parsed['result']
  end

  # A 404 here means this server has no `/jsonrpc`, which is a statement about the TRANSPORT rather than about
  # the request -- the caller re-detects the version instead of reporting the document as broken.
  def http_error(status)
    case status
    when 300..399 then Odoo::Error.new('INVALID_URL', reason: 'redirect', http_status: status)
    when 401, 403 then Odoo::Error.new('AUTH_INVALID', reason: 'rejected', http_status: status)
    when 404 then Odoo::Error.new('ENDPOINT_MISSING', reason: 'no_jsonrpc', http_status: status)
    when 429 then Odoo::Error.new('RATE_LIMITED', http_status: status)
    when 500..599 then Odoo::Error.new('SERVER_ERROR', reason: "http_#{status}", http_status: status)
    else Odoo::Error.new('INVALID_RESPONSE', reason: "http_#{status}", http_status: status)
    end
  end

  # `debug` holds a Python traceback and is never carried: `message` is Odoo's own one-line explanation, which
  # is the part that tells an operator which journal setting is wrong, and it is scrubbed before storage.
  def rpc_error(error)
    data = error['data'].presence || {}
    name = data['name'].to_s
    Odoo::Error.new(EXCEPTIONS.fetch(name, 'SERVER_ERROR'), reason: name.presence&.split('.')&.last,
                                                            detail: Odoo::SyncAttempt.scrub(data['message'].presence || error['message']))
  end
end
