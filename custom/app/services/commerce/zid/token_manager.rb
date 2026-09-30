# Keeps a Zid store's tokens usable (docs/commerce/14-zid-oauth-and-tokens.md §lifecycle), with the lifecycle of
# Commerce::TokenManager.
#
# Zid's tokens live about a year. They are refreshed REFRESH_BEFORE their expiry, and when Zid rejects them earlier (401):
# Zid's documented recovery is one refresh and one retry, then the merchant authorizes again. Zid does not document its
# refresh tokens as single-use, so that is not assumed; still, the refresh request is sent once, without retries. Zid
# answering a refresh with unusable tokens moves the store to needs_reauth.
class Commerce::Zid::TokenManager < Commerce::TokenManager
  REFRESH_BEFORE = 60.days
  RETRY_AFTER = 1.hour
  TOKEN_KEYS = %w[authorization access_token refresh_token token_type scope expires_at].freeze

  private

  # No expiry from Zid means the token is only refreshed once Zid rejects it.
  def refresh_due?
    expires_at = authorized_credentials['expires_at']
    expires_at.present? && Time.iso8601(expires_at) <= REFRESH_BEFORE.from_now
  end

  def expired?
    Time.iso8601(@store.credentials['expires_at']) <= Time.current
  end

  # The saved credentials, or the Commerce::Error of a refresh that can be tried again later.
  def request_refresh
    status, body = Commerce::Zid::Oauth.token(grant_type: 'refresh_token', refresh_token: @store.credentials['refresh_token'])
    return failure(status, body) unless status == 200

    save(Commerce::Zid::Tokens.credentials(body), 'expires_at')
  rescue Commerce::Error => e
    raise if e.code == 'AUTH_INVALID'
    raise needs_reauth!('refresh_response_invalid') if e.reason == 'zid_tokens'

    e
  end
end
