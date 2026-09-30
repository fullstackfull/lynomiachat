# The OAuth tokens of a Salla installation, in the shape stored in Commerce::Store#credentials (encrypted at rest).
#
# Lynomia only reads from Salla, so an installation must grant exactly read access: the required read scopes plus
# offline_access (without it Salla issues no refresh token). Tokens that carry any write scope are refused and never
# stored (docs/commerce/11-salla-auth-and-token-lifecycle.md §scopes).
module Commerce::Salla::Tokens
  REQUIRED_SCOPES = %w[offline_access customers.read orders.read shipping.read].freeze

  # From `app.store.authorize` data (`expires`: a Unix timestamp) or a refresh response (`expires`, or `expires_in`
  # seconds). `token_type` is compared case-insensitively, as OAuth 2.0 defines it (RFC 6749 §7.1).
  def self.credentials(data, now: Time.current)
    access, refresh, scope, type = data.values_at('access_token', 'refresh_token', 'scope', 'token_type')
    expires_at = expiry(data, now)
    valid = [access, refresh, scope].all? { |value| value.is_a?(String) && value.present? } && type.is_a?(String) && type.casecmp?('bearer')
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'salla_tokens') unless valid && expires_at

    check_scopes!(scope)
    { 'access_token' => access, 'refresh_token' => refresh, 'token_type' => 'bearer', 'scope' => scope,
      'access_token_expires_at' => expires_at.utc.iso8601, 'refresh_token_expires_at' => nil }
  end

  def self.check_scopes!(scope)
    granted = scope.split
    raise Commerce::Error.new('PERMISSION_DENIED', reason: 'salla_write_scope') if granted.any? do |name|
      name != 'offline_access' && !name.end_with?('.read')
    end
    raise Commerce::Error.new('PERMISSION_DENIED', reason: 'salla_missing_scope') unless (REQUIRED_SCOPES - granted).empty?
  end

  def self.expiry(data, now)
    if data['expires'].is_a?(Integer) then Time.zone.at(data['expires'])
    elsif data['expires_in'].is_a?(Integer) then now + data['expires_in']
    end
  end
  private_class_method :check_scopes!, :expiry
end
