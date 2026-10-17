# The one way this integration speaks to a network (docs/odoo/03-adapter.md §1).
#
# EVERYTHING HERE IS A COPY OF A DECISION Commerce::HttpClient already made for store APIs, for the same
# reasons, against the same class of risk -- an operator-supplied hostname that the server will then connect
# to:
#
#   * every request goes through SsrfFilter, which resolves the host, refuses private, loopback, link-local
#     and cloud-metadata addresses, and pins the connection to the address it checked, so DNS cannot be
#     rebound between the check and the connect;
#   * redirects are NEVER followed -- a 3xx is an error -- so nothing can bounce an authenticated accounting
#     request to another host;
#   * bounded: connect 5 s, read 30 s, whole body 20 s and 5 MB. The read timeout is longer than Commerce's
#     8 s because posting an invoice makes Odoo compute taxes and sequences, which is slower than reading an
#     order;
#   * TLS verification is never disabled and https is never relaxed -- the profile refuses a non-https base
#     URL at validation time and this refuses to build a non-https request;
#   * NOTHING IS RETRIED HERE. Retrying is a decision about an accounting write, so it belongs to the caller
#     that knows whether the write was idempotent (Odoo::SyncEvent and its backoff), not to the socket.
#
# WHAT IT DOES NOT LOG. Not the Authorization header, not the API key, not the request body (which carries the
# key on the legacy transport), not the response body. The one log line is the method, the path, the status
# and the elapsed time.
class Odoo::Http
  HTTP_OPTIONS = { open_timeout: 5, read_timeout: 30, write_timeout: 10, ssl_timeout: 5 }.freeze
  BODY_DEADLINE = 20
  MAX_BODY_BYTES = 5.megabytes
  USER_AGENT = 'Lynomia-Odoo/1.0'.freeze

  # Failures that happen before a request is written: the server cannot have acted on it.
  NOT_SENT_ERRORS = [SsrfFilter::Error, Net::OpenTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
                     Errno::ENETUNREACH, SocketError].freeze
  # Failures after the request went out. The server MAY have acted, so these are never quietly repeated.
  UNKNOWN_OUTCOME_ERRORS = [Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET, EOFError, IOError,
                            OpenSSL::SSL::SSLError].freeze

  def initialize(base_url:, log_tag:)
    @base_uri = URI.parse(base_url.to_s)
    @log_tag = log_tag
  end

  # One JSON POST. Returns [status, parsed body or nil] for ANY HTTP status, because Odoo answers a business
  # refusal with a 200 carrying an error object on one transport and with a 4xx on the other, and only the
  # transport knows which. Raises Odoo::Error only when there is no answer to classify.
  def post_json(path, body, headers: {})
    raise Odoo::Error.new('INVALID_URL', reason: 'not_https') unless @base_uri.scheme == 'https'

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @body = +''
    response = perform(build_uri(path), body.to_json, headers)
    log(path, response.code, started)
    [response.code.to_i, parse_json]
  rescue *NOT_SENT_ERRORS => e
    raise Odoo::Error.new(unreachable_code(e), reason: unreachable_reason(e))
  rescue *UNKNOWN_OUTCOME_ERRORS => e
    raise Odoo::Error.new('TIMEOUT', reason: e.is_a?(OpenSSL::SSL::SSLError) ? 'tls' : 'no_answer')
  end

  private

  def build_uri(path)
    uri = @base_uri.dup
    uri.path = "#{@base_uri.path.chomp('/')}#{path}"
    uri.query = nil
    uri
  end

  # `max_redirects: 0` with `allow_unfollowed_redirects: true` hands the 3xx back instead of following it; the
  # transport then classifies it, so a redirect is a visible error rather than a silent host change.
  def perform(uri, payload, headers)
    SsrfFilter.post(uri, max_redirects: 0, allow_unfollowed_redirects: true, http_options: HTTP_OPTIONS,
                         headers: request_headers(headers), body: payload) do |response|
      read_body(response)
    end
  end

  def request_headers(extra)
    { 'Accept' => 'application/json', 'Content-Type' => 'application/json', 'User-Agent' => USER_AGENT }.merge(extra).compact
  end

  def read_body(response)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BODY_DEADLINE
    response.read_body do |chunk|
      @body << chunk
      raise Odoo::Error.new('INVALID_RESPONSE', reason: 'too_large') if @body.bytesize > MAX_BODY_BYTES
      raise Odoo::Error.new('TIMEOUT', reason: 'body_deadline') if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end
  end

  # nil rather than a raise: an Odoo error page is HTML, and the transport decides whether an unparseable body
  # at this status is a problem. A 500 with an HTML body is a SERVER_ERROR, not a parse failure.
  def parse_json
    return nil if @body.blank?

    JSON.parse(@body)
  rescue JSON::ParserError
    nil
  end

  def unreachable_code(error)
    error.is_a?(SsrfFilter::PrivateIPAddress) ? 'INVALID_URL' : 'UNREACHABLE'
  end

  def unreachable_reason(error)
    case error
    when SsrfFilter::PrivateIPAddress then 'private_address'
    when SsrfFilter::UnresolvedHostname then 'dns'
    when SsrfFilter::Error then 'refused_destination'
    when Net::OpenTimeout then 'connect_timeout'
    else 'connection'
    end
  end

  def log(path, status, started)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Rails.logger.info("[Odoo] #{@log_tag} POST #{path} -> #{status} in #{elapsed}ms")
  end
end
