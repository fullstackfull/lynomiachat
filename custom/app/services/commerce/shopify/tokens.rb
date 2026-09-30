# The expiring offline token of a Shopify app authorization, in the shape stored in Commerce::Store#credentials
# (encrypted at rest; docs/commerce/18-shopify-oauth-and-tokens.md).
#
# Shopify answers both grants with { access_token, scope, expires_in, refresh_token, refresh_token_expires_in }. Only
# that is stored, with both expiry times computed from Shopify's own values, never assumed. Anything else is refused: a
# response without a refresh token or expiries is a non-expiring token, and one with `associated_user` is an online
# token, bound to a staff member's session.
module Commerce::Shopify::Tokens
  def self.credentials(body, now: Time.current)
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'shopify_tokens') unless expiring_offline?(body)

    { 'access_token' => body['access_token'], 'access_token_expires_at' => (now + body['expires_in']).utc.iso8601,
      'refresh_token' => body['refresh_token'], 'refresh_token_expires_at' => (now + body['refresh_token_expires_in']).utc.iso8601,
      'scope' => body['scope'] }
  end

  def self.expiring_offline?(body)
    body.is_a?(Hash) && !body.key?('associated_user') &&
      body.values_at('access_token', 'refresh_token', 'scope').all?(/\S/) &&
      body.values_at('expires_in', 'refresh_token_expires_in').all? { |seconds| seconds.is_a?(Integer) && seconds.positive? }
  end
  private_class_method :expiring_offline?
end
