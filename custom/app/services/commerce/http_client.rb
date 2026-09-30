# Read-only JSON client for merchant-hosted store APIs (docs/commerce/08-woocommerce-security.md).
#
# - Every request goes through SsrfFilter: the host is resolved, private/loopback/link-local/metadata addresses are
#   refused and the connection is pinned to the checked IP (no DNS rebinding between check and connect).
# - Redirects are never followed: a 3xx is an INVALID_STORE_URL error, so nothing can bounce us to another host.
# - Bounded: connect 3 s, each read 8 s, whole body 10 s and 5 MB. One retry, GET only, for a dropped connection or a
#   502/503/504; timeouts are not retried so a slow store costs at most one timeout.
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
  USER_AGENT = 'Lynomia-Commerce/1.0'.freeze

  def initialize(base_uri:, username:, password:, log_tag:)
    @base_uri = base_uri
    @username = username
    @password = password
    @log_tag = log_tag
  end

  def get_json(path, params = {})
    uri = @base_uri.dup
    uri.path = "#{@base_uri.path}#{path}"
    uri.query = params.presence && URI.encode_www_form(params)
    with_retry { request(uri) }
  end

  private

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

  def request(uri)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @body = +''
    response = Commerce::StoreUrl.trusted_host?(uri.host) ? fetch_trusted(uri) : fetch(uri)
    log(uri, response.code, started)
    parse(response)
  rescue SsrfFilter::PrivateIPAddress
    raise Commerce::Error.new('INVALID_STORE_URL', reason: 'private_address')
  rescue SsrfFilter::UnresolvedHostname
    raise Commerce::Error.new('STORE_UNAVAILABLE', reason: 'dns')
  rescue SsrfFilter::Error
    raise Commerce::Error.new('INVALID_STORE_URL', reason: 'invalid')
  rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
    raise Commerce::Error, 'TIMEOUT'
  end

  def fetch(uri)
    SsrfFilter.get(uri, max_redirects: 0, allow_unfollowed_redirects: true, http_options: HTTP_OPTIONS,
                        headers: headers, request_proc: ->(req) { req.basic_auth(@username, @password) }) do |response|
      read_body(response)
    end
  end

  def fetch_trusted(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', **HTTP_OPTIONS) do |http|
      req = Net::HTTP::Get.new(uri)
      headers.each { |name, value| req[name] = value }
      req.basic_auth(@username, @password)
      http.request(req) { |response| read_body(response) }
    end
  end

  def headers
    { 'Accept' => 'application/json', 'User-Agent' => USER_AGENT }
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

  def parse_json
    JSON.parse(@body)
  rescue JSON::ParserError
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'not_json')
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

  def log(uri, status, started)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Rails.logger.info("[Commerce:#{@log_tag}] GET #{uri.path} status=#{status} ms=#{elapsed}")
  end
end
