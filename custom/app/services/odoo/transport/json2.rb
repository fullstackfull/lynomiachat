# Odoo 19's External JSON-2 API (docs/odoo/03-adapter.md §1).
#
# `POST /json/2/<model>/<method>` with `Authorization: Bearer <api_key>`. It is the endpoint Odoo's own 19.0
# documentation names as the replacement for `/xmlrpc`, `/xmlrpc/2` and `/jsonrpc`, all three of which it
# schedules for removal in Odoo 22 (autumn 2028) and Online 21.1 (winter 2027). It is served by the `rpc`
# addon, which is `auto_install: True`, so it is present on an ordinary Odoo 19 install with nothing for the
# customer to enable.
#
# THREE THINGS IT DOES BETTER than the legacy endpoint, and they matter here:
#   * one step, not two. The API key identifies the user, so there is no `authenticate` round trip and no uid
#     to carry -- and therefore no second place for a credential to appear;
#   * the key travels in a HEADER rather than inside the request body, so it cannot reach a body-logging proxy;
#   * arguments are bound against the real Python signature, so a misspelled parameter is a 422 rather than a
#     silently ignored keyword.
#
# ARGUMENTS ARE NAMED ONLY. The endpoint has no way to express a positional argument, which is why this
# integration's whole call vocabulary is named -- `vals_list:` for create, `vals:` for write, `domain:` and
# `fields:` for search_read. The legacy transport can express named arguments too, so one description serves
# both; the reverse would not be true.
#
# NO CROSS-CALL TRANSACTION. Odoo's documentation is explicit: "All calls to the JSON-2 endpoint run in their
# own SQL transaction" and "it is not possible to chain multiple calls inside a single transaction". Creating
# an invoice and posting it are therefore two transactions, and this integration never claims otherwise.
class Odoo::Transport::Json2
  NAME = 'json2'.freeze
  # Version detection has no model and no method, so it does not go through this endpoint at all -- see
  # Odoo::VersionProbe, which asks the legacy endpoint before any credential exists.
  PATH_PREFIX = '/json/2/'.freeze

  # Odoo exception names arrive in the error object's `name`, the same values as on the legacy transport.
  EXCEPTIONS = Odoo::Transport::JsonRpc::EXCEPTIONS

  def initialize(profile, http: nil)
    @profile = profile
    @http = http || Odoo::Http.new(base_url: profile.base_url, log_tag: NAME)
  end

  # `ids` is an array in the body, empty for an @api.model method -- and passing a non-empty one to an
  # @api.model method is a 422 rather than a silent success, which is why create() sends none.
  def call(model:, method:, ids: [], named: {}, context: {})
    body = { ids: Array(ids), context: merged_context(context) }.merge(named.symbolize_keys)
    status, parsed = @http.post_json("#{PATH_PREFIX}#{model}/#{method}", body, headers: auth_headers)
    interpret(status, parsed)
  end

  private

  def auth_headers
    key = @profile.api_key.presence or raise Odoo::Error.new('NOT_CONFIGURED', reason: 'api_key_missing')
    # X-Odoo-Database is only needed when one server hosts several databases without a Host-based dbfilter.
    # Sent always, because a wrong-database answer is worse than a redundant header.
    { 'Authorization' => "Bearer #{key}", 'X-Odoo-Database' => @profile.database }
  end

  def merged_context(context)
    Odoo::SourceStamp.new(@profile).call_context.merge(context.to_h.stringify_keys)
  end

  # On this endpoint the HTTP status carries the verdict, unlike JSON-RPC where everything is a 200. A 2xx body
  # IS the result -- a recordset comes back as its id list, so `[42]` from create is the created id.
  def interpret(status, parsed)
    return parsed if status.between?(200, 299)

    raise error_for(status, parsed.is_a?(Hash) ? parsed : {})
  end

  def error_for(status, payload)
    name = payload['name'].to_s
    detail = Odoo::SyncAttempt.scrub(payload['message'])
    code = EXCEPTIONS[name] || http_code(status)
    Odoo::Error.new(code, reason: reason_for(status, name), detail: detail, http_status: status)
  end

  # A table rather than a chain of branches, because these are facts about statuses and not decisions. The
  # 404 is the interesting one: it means the server has no JSON-2 route, so it is older than 19 or the `rpc`
  # addon is absent -- a statement about the TRANSPORT, which is why the caller re-detects the version instead
  # of reporting the document as broken.
  STATUS_CODES = { 401 => 'AUTH_INVALID', 403 => 'PERMISSION_DENIED', 404 => 'ENDPOINT_MISSING',
                   422 => 'INVALID_REQUEST', 429 => 'RATE_LIMITED' }.freeze

  def http_code(status)
    return STATUS_CODES[status] if STATUS_CODES.key?(status)
    return 'INVALID_URL' if status.between?(300, 399)
    return 'SERVER_ERROR' if status.between?(500, 599)

    'INVALID_RESPONSE'
  end

  def reason_for(status, name)
    return name.split('.').last if name.present?

    status == 404 ? 'no_json2' : "http_#{status}"
  end
end
