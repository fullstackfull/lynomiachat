# A store's recovery link as an agent may send it (docs/commerce/31-sales-recovery.md §URL safety): https only, on the
# store's own host or its provider's checkout hosts, no credentials, no other port, at most MAX_LENGTH. Anything else
# (javascript:, data:, file:, http:, another host, a shortener) is refused: the cart then offers no recovery message.
# The link is never taken from an agent or a request: only from the store's own cart.
module Commerce::RecoveryUrl
  MAX_LENGTH = 2048

  # `hosts`: exact hosts, or ".suffix" entries for a provider's own subdomains (".zid.store").
  def self.safe(url, hosts:)
    value = url.to_s.strip
    return if value.empty? || value.length > MAX_LENGTH || value.match?(/\s/)

    uri = URI.parse(value)
    uri.to_s if https?(uri) && allowed?(uri.host.to_s.downcase, hosts)
  rescue URI::InvalidURIError
    nil
  end

  def self.https?(uri) = uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && [nil, 443].include?(uri.port)

  def self.allowed?(host, hosts)
    host.present? && hosts.compact.map(&:downcase).any? { |entry| entry.start_with?('.') ? host.end_with?(entry) : host == entry }
  end

  private_class_method :https?, :allowed?
end
