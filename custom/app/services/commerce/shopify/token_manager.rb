# Keeps a Shopify store's expiring offline token usable (docs/commerce/18-shopify-oauth-and-tokens.md §refresh), with the
# lifecycle of Commerce::TokenManager: refreshed under the store's lock, re-read first, the new pair saved in one write.
#
# The access token lives about an hour and is refreshed REFRESH_BEFORE its expiry; Shopify answers a refresh with a new
# access token and a new refresh token, both with their own expiry. These rules follow Shopify's documentation, not the
# other providers':
# - a refresh that failed on a timeout, a network failure, a 5xx or an unreadable answer is sent again once, right away,
#   with the same refresh token: Shopify returns the same new pair for a repeated refresh and keeps the previous refresh
#   token until the new access token is used. If that fails too, the tokens stay and the refresh waits RETRY_AFTER;
# - a refresh token past its own expiry, or one Shopify refuses (400/401: revoked by an uninstall, invalid), means the
#   merchant authorizes again: no request is sent for an expired one.
class Commerce::Shopify::TokenManager < Commerce::TokenManager
  REFRESH_BEFORE = 5.minutes
  RETRY_AFTER = 1.minute
  TOKEN_KEYS = %w[access_token access_token_expires_at refresh_token refresh_token_expires_at scope].freeze

  private

  def refresh_due?
    Time.iso8601(authorized_credentials['access_token_expires_at']) <= REFRESH_BEFORE.from_now
  end

  def expired?
    Time.iso8601(@store.credentials['access_token_expires_at']) <= Time.current
  end

  def request_refresh
    raise needs_reauth!('refresh_token_expired') if Time.iso8601(@store.credentials['refresh_token_expires_at']) <= Time.current

    outcome = send_refresh
    outcome.is_a?(Commerce::Error) && outcome.code != 'RATE_LIMITED' ? send_refresh : outcome
  end

  # The saved credentials, or the Commerce::Error of a refresh that can be sent again.
  def send_refresh
    grant = { grant_type: 'refresh_token', refresh_token: @store.credentials['refresh_token'] }
    status, body = Commerce::Shopify::Oauth.token(URI(@store.base_url).host, grant)
    return failure(status, body) unless status == 200

    save(Commerce::Shopify::Tokens.credentials(body), 'access_token_expires_at')
  rescue Commerce::Error => e
    raise if e.code == 'AUTH_INVALID'

    e
  end
end
