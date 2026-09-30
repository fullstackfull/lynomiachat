# Parses and normalizes a merchant-supplied store URL before anything is stored or requested
# (docs/commerce/08-woocommerce-security.md). Syntax, scheme and port are checked here; the IP the host resolves to is
# checked on every request by SsrfFilter in Commerce::HttpClient, which also pins the connection to that IP.
#
# COMMERCE_TRUSTED_STORE_HOSTS (comma-separated exact host names) is the explicit internal-host policy: only those
# hosts may use http, a non-default port or a private address (development and staging stores).
class Commerce::StoreUrl
  REASONS = %w[invalid https_required port_not_allowed ip_address_not_allowed private_address redirect].freeze

  def self.parse(raw)
    new(raw).parse
  end

  def self.trusted_host?(host)
    ENV.fetch('COMMERCE_TRUSTED_STORE_HOSTS', '').split(',').map { |entry| entry.strip.downcase }.compact_blank.include?(host.to_s.downcase)
  end

  # Stable store identity for ownership: the host (with a non-default port) and path we actually connected to.
  # Self-declared identifiers from the store (WordPress `home`, WooCommerce store UUID) are not used: a store could
  # claim another merchant's value, and cloned staging sites share the UUID.
  def self.external_id(uri)
    port = uri.port == uri.default_port ? '' : ":#{uri.port}"
    "#{uri.host}#{port}#{uri.path}"
  end

  def initialize(raw)
    @raw = raw.to_s.strip
  end

  def parse
    uri = parse_uri
    trusted = self.class.trusted_host?(uri.host)
    invalid!('https_required') unless uri.scheme == 'https' || trusted
    invalid!('port_not_allowed') unless uri.port == uri.default_port || trusted
    invalid!('ip_address_not_allowed') if ip_address?(uri.host) && !trusted

    uri
  end

  private

  def parse_uri
    uri = URI.parse(@raw.match?(%r{\A[a-z][a-z0-9+.-]*://}i) ? @raw : "https://#{@raw}")
    invalid!('invalid') unless plain_http_uri?(uri)

    uri.host = uri.host.downcase
    uri.path = uri.path.sub(%r{/+\z}, '')
    uri
  rescue URI::InvalidURIError
    invalid!('invalid')
  end

  def plain_http_uri?(uri)
    uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank? && uri.query.blank? && uri.fragment.blank? &&
      uri.path.exclude?('..')
  end

  def ip_address?(host)
    IPAddr.new(host.delete_prefix('[').delete_suffix(']'))
    true
  rescue IPAddr::InvalidAddressError
    false
  end

  def invalid!(reason)
    raise Commerce::Error.new('INVALID_STORE_URL', reason: reason)
  end
end
