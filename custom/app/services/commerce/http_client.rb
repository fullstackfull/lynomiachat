# JSON client for store APIs: merchant-hosted ones (WooCommerce), fixed platform APIs (Salla, Zid) and each Shopify shop's
# myshopify.com host. Every provider uses it, so the limits below are the same everywhere
# (docs/commerce/08-woocommerce-security.md, 12-salla-security.md).
#
# - Every request goes through SsrfFilter: the host is resolved, private/loopback/link-local/metadata addresses are
#   refused and the connection is pinned to the checked IP (no DNS rebinding between check and connect).
# - Redirects are never followed: a 3xx is an INVALID_STORE_URL error, so nothing can bounce us to another host.
# - Bounded: connect 3 s, each read 8 s, whole body 10 s and 5 MB. One retry, GET only, for a dropped connection or a
#   502/503/504; timeouts are not retried so a slow store costs at most one timeout. POST and DELETE are never retried.
# - Hosts listed in COMMERCE_TRUSTED_STORE_HOSTS (development/staging stores on internal addresses) skip the address
#   check only; they get the same limits and no redirects either.
# - Errors are Commerce::Error codes. Credentials, query strings and response bodies are never logged or raised.
class Commerce::HttpClient
  HTTP_OPTIONS = { open_timeout: 3, read_timeout: 8, write_timeout: 8, ssl_timeout: 3 }.freeze
  BODY_DEADLINE = 10
  MAX_BODY_BYTES = 5.megabytes
  RETRYABLE_REASONS = %w[http_502 http_503 http_504].freeze
  CONNECTION_ERRORS = [Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, EOFError, IOError,
                       SocketError, OpenSSL::SSL::SSLError].freeze
  RETRYABLE_ERRORS = [Errno::ECONNRESET, EOFError].freeze
  # Failures that happen before a request is written: the server cannot have acted on it.
  NOT_SENT_ERRORS = [SsrfFilter::Error, Net::OpenTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
                     SocketError].freeze
  RATE_LIMIT_HEADERS = { limit: 'X-RateLimit-Limit', remaining: 'X-RateLimit-Remaining', reset: 'X-RateLimit-Reset',
                         retry_after: 'Retry-After' }.freeze
  USER_AGENT = 'Lynomia-Commerce/1.0'.freeze

  # Rate-limit headers of the last response ({ limit:, remaining:, reset:, retry_after: }, integers or nil).
  attr_reader :rate_limit

  # `authorization` is the whole Authorization header value ("Basic …", "Bearer …"), or nil for none. `headers` are further
  # fixed request headers (Zid's X-Manager-Token).
  def initialize(base_uri:, log_tag:, authorization: nil, headers: {})
    @base_uri = base_uri
    @authorization = authorization
    @extra_headers = headers
    @log_tag = log_tag
  end

  def get_json(path, params = {})
    uri = build_uri(path, params)
    with_retry { parse(transport_errors { perform(:get, uri) }) }
  end

  # One form POST, never retried: OAuth token requests, where sending twice could spend a single-use refresh token twice.
  # Returns [status, parsed JSON body or nil] for any HTTP response, so the caller classifies OAuth errors itself. A
  # transport failure raises Commerce::Error with reason 'not_sent' when the request provably never reached the server
  # (DNS, refused connection, connect timeout) and 'unknown_outcome' when the server may have processed it.
  def post_form(path, form)
    post_once(path, URI.encode_www_form(form), 'application/x-www-form-urlencoded')
  end

  # The same single request with a JSON body (Shopify's token endpoint).
  def post_json_status(path, body)
    post_once(path, body.to_json, 'application/json')
  end

  # One JSON POST, never retried (a webhook subscription could be created twice). Returns the parsed body of a 2xx answer.
  def post_json(path, body)
    parse(transport_errors { perform(:post, build_uri(path), body.to_json, 'application/json') })
  end

  # One DELETE, never retried. Returns the HTTP status of a 2xx answer.
  def delete(path, params = {})
    status = transport_errors { perform(:delete, build_uri(path, params)) }.code.to_i
    raise error_for(status) unless status.between?(200, 299)

    status
  end

  private

  def post_once(path, body, content_type)
    response = perform(:post, build_uri(path), body, content_type)
    [response.code.to_i, parse_json(strict: false)]
  rescue *NOT_SENT_ERRORS
    raise Commerce::Error.new('STORE_UNAVAILABLE', reason: 'not_sent')
  rescue Commerce::Error, Net::ReadTimeout, Net::WriteTimeout, *CONNECTION_ERRORS
    raise Commerce::Error.new('TIMEOUT', reason: 'unknown_outcome')
  end

  def build_uri(path, params = {})
    uri = @base_uri.dup
    uri.path = "#{@base_uri.path}#{path}"
    uri.query = params.presence && URI.encode_www_form(params)
    uri
  end

  def with_retry
    attempts = 0
    begin
      attempts += 1
      yield
    rescue Commerce::Error, *CONNECTION_ERRORS => e
      raise translate(e) unless attempts == 1 && retryable?(e)

      retry
    end
  end

  def retryable?(error)
    RETRYABLE_ERRORS.any? { |klass| error.instance_of?(klass) } ||
      (error.is_a?(Commerce::Error) && RETRYABLE_REASONS.include?(error.reason))
  end

  def transport_errors
    yield
  rescue SsrfFilter::PrivateIPAddress
    raise Commerce::Error.new('INVALID_STORE_URL', reason: 'private_address')
  rescue SsrfFilter::UnresolvedHostname
    raise Commerce::Error.new('STORE_UNAVAILABLE', reason: 'dns')
  rescue SsrfFilter::Error
    raise Commerce::Error.new('INVALID_STORE_URL', reason: 'invalid')
  rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
    raise Commerce::Error, 'TIMEOUT'
  end

  def perform(verb, uri, body = nil, content_type = nil)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @body = +''
    request_headers = headers(content_type)
    response = if Commerce::StoreUrl.trusted_host?(uri.host)
                 fetch_trusted(verb, uri, body, request_headers)
               else
                 fetch(verb, uri, body, request_headers)
               end
    @rate_limit = RATE_LIMIT_HEADERS.transform_values { |name| Integer(response[name].to_s, 10, exception: false) }
    log(verb, uri, response.code, started)
    response
  end

  def fetch(verb, uri, body, headers)
    SsrfFilter.public_send(verb, uri, max_redirects: 0, allow_unfollowed_redirects: true, http_options: HTTP_OPTIONS,
                                      headers: headers, body: body) do |response|
      read_body(response)
    end
  end

  def fetch_trusted(verb, uri, body, headers)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', **HTTP_OPTIONS) do |http|
      req = Net::HTTP.const_get(verb.to_s.capitalize).new(uri)
      headers.each { |name, value| req[name] = value }
      req.body = body if body
      http.request(req) { |response| read_body(response) }
    end
  end

  def headers(content_type)
    { 'Accept' => 'application/json', 'User-Agent' => USER_AGENT, 'Authorization' => @authorization,
      'Content-Type' => content_type }.merge(@extra_headers).compact
  end

  def read_body(response)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BODY_DEADLINE
    response.read_body do |chunk|
      @body << chunk
      raise Commerce::Error.new('INVALID_RESPONSE', reason: 'too_large') if @body.bytesize > MAX_BODY_BYTES
      raise Commerce::Error, 'TIMEOUT' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end
  end

  def parse(response)
    status = response.code.to_i
    return parse_json if status.between?(200, 299)

    raise error_for(status)
  end

  def parse_json(strict: true)
    JSON.parse(@body)
  rescue JSON::ParserError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'not_json') if strict
  end

  def error_for(status)
    case status
    when 300..399 then Commerce::Error.new('INVALID_STORE_URL', reason: 'redirect')
    when 401 then Commerce::Error.new('AUTH_INVALID')
    when 403 then Commerce::Error.new('PERMISSION_DENIED')
    when 404 then Commerce::Error.new('NOT_FOUND')
    when 429 then Commerce::Error.new('RATE_LIMITED')
    when 500..599 then Commerce::Error.new('STORE_UNAVAILABLE', reason: "http_#{status}")
    else Commerce::Error.new('INVALID_RESPONSE', reason: "http_#{status}")
    end
  end

  def translate(error)
    return error if error.is_a?(Commerce::Error)

    Commerce::Error.new('STORE_UNAVAILABLE', reason: error.is_a?(OpenSSL::SSL::SSLError) ? 'tls' : 'connection')
  end

  def log(verb, uri, status, started)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Commerce::Metrics.event('commerce.provider.request', client: @log_tag, method: verb.upcase, path: uri.path, status: status, ms: elapsed)
  end
end
