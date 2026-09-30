# The OAuth tokens of a Zid authorization, in the shape stored in Commerce::Store#credentials (encrypted at rest).
#
# Zid answers both grants with { access_token, authorization, refresh_token, expires_in }: `authorization` is sent as
# `Authorization: Bearer`, `access_token` as `X-Manager-Token` (docs/commerce/14-zid-oauth-and-tokens.md). Only what Zid
# sends is stored: token_type and scope when present, and no expiry when expires_in is missing (then the token is only
# refreshed after Zid rejects it). Zid sends no refresh-token expiry, so none is stored.
module Commerce::Zid::Tokens
  def self.credentials(body, now: Time.current)
    body = {} unless body.is_a?(Hash)
    tokens = { 'authorization' => body['authorization'] || body['Authorization'], 'access_token' => body['access_token'],
               'refresh_token' => body['refresh_token'] }
    raise Commerce::Error.new('INVALID_RESPONSE', reason: 'zid_tokens') unless tokens.values.all? { |value| text?(value) }

    tokens.merge(body.slice('token_type', 'scope').select { |_, value| text?(value) }, 'expires_at' => expiry(body['expires_in'], now))
  end

  def self.text?(value) = value.is_a?(String) && value.present?

  def self.expiry(expires_in, now)
    seconds = Integer(expires_in.to_s, 10, exception: false)
    (now + seconds).utc.iso8601 if seconds&.positive?
  end
  private_class_method :text?, :expiry
end
