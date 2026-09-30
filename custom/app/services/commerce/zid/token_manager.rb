# Keeps a Zid store's tokens usable (docs/commerce/14-zid-oauth-and-tokens.md §lifecycle).
#
# Zid's tokens live about a year. They are refreshed REFRESH_BEFORE their expiry, and when Zid rejects them earlier (401):
# Zid's documented recovery is one refresh and one retry, then the merchant authorizes again. Zid does not document its
# refresh tokens as single-use, so that is not assumed; still, a refresh is never sent twice at once:
#   1. it runs only under the store's lock (Commerce::StoreLock), after re-reading the store, since another process may
#      have just refreshed it: concurrent readers wait, then use the new tokens;
#   2. the request is sent once, without retries, and the new tokens are saved in one write.
# A refresh that fails for a reason that can pass (Zid unavailable or rate limited, an answer lost in transit) keeps the
# tokens, and no refresh is tried again for RETRY_AFTER; meanwhile a token that has not expired is still used. Zid
# refusing the refresh token (revoked by an uninstall, expired) or answering with unusable tokens moves the store to
# needs_reauth: its tokens and cached data are removed and an administrator connects it again.
class Commerce::Zid::TokenManager
  REFRESH_BEFORE = 60.days
  RETRY_AFTER = 1.hour
  TOKEN_KEYS = %w[authorization access_token refresh_token token_type scope expires_at].freeze

  def initialize(store)
    @store = store
  end

  # Runs the block with usable credentials. When Zid rejects them (AUTH_INVALID), they are refreshed once and the block
  # runs once more; rejected again, the authorization is gone and the store needs re-authorization.
  def with_credentials(&)
    current = credentials
    yield current
  rescue Commerce::Error => e
    raise unless e.code == 'AUTH_INVALID' && current

    retry_with(renew(current), &)
  end

  # The stored credentials, refreshed first when they expire within REFRESH_BEFORE.
  def credentials
    return authorized_credentials unless refresh_due?

    Commerce::StoreLock.with('zid', @store.external_store_id) do
      @store.reload
      refresh_due? ? refresh(expired: expired?) : authorized_credentials
    end
  end

  private

  # After Zid rejected `rejected`: the tokens another process saved meanwhile, or one refresh here. Until a refresh
  # succeeds the error stays AUTH_INVALID, so nothing cached is served over tokens Zid refused.
  def renew(rejected)
    Commerce::StoreLock.with('zid', @store.external_store_id) do
      @store.reload
      authorized_credentials['access_token'] == rejected['access_token'] ? refresh(expired: true) : @store.credentials
    end
  rescue Commerce::Error => e
    raise if e.code == 'AUTH_INVALID'

    raise Commerce::Error.new('AUTH_INVALID', reason: 'zid_refresh_pending')
  end

  def retry_with(renewed)
    yield renewed
  rescue Commerce::Error => e
    raise needs_reauth!('tokens_rejected') if e.code == 'AUTH_INVALID'

    raise
  end

  def authorized_credentials
    raise Commerce::Error, 'AUTH_INVALID' if @store.needs_reauth? || @store.credentials.blank? || @store.credentials['refresh_token'].blank?

    @store.credentials
  end

  # No expiry from Zid means the token is only refreshed once Zid rejects it.
  def refresh_due?
    expires_at = authorized_credentials['expires_at']
    expires_at.present? && Time.iso8601(expires_at) <= REFRESH_BEFORE.from_now
  end

  def expired?
    Time.iso8601(@store.credentials['expires_at']) <= Time.current
  end

  # `expired`: the current token cannot be used any more, so a refresh that has to wait is an error, not a later retry.
  def refresh(expired:)
    outcome = backing_off? ? Commerce::Error.new('STORE_UNAVAILABLE', reason: 'zid_refresh_backoff') : request_refresh
    outcome.is_a?(Commerce::Error) ? retry_later(expired, outcome) : outcome
  end

  # The saved credentials, or the Commerce::Error of a refresh that can be tried again later.
  def request_refresh
    status, body = Commerce::Zid::Oauth.token(grant_type: 'refresh_token', refresh_token: @store.credentials['refresh_token'])
    return save(body) if status == 200

    failure(status, body.is_a?(Hash) ? body['error'] : nil)
  rescue Commerce::Error => e
    raise if e.code == 'AUTH_INVALID'

    e
  end

  def failure(status, oauth_error)
    return Commerce::Error.new('RATE_LIMITED') if status == 429
    return Commerce::Error.new('STORE_UNAVAILABLE', reason: 'zid_client_rejected') if oauth_error == 'invalid_client'
    raise needs_reauth!('refresh_token_rejected') if [400, 401].include?(status)

    Commerce::Error.new('STORE_UNAVAILABLE', reason: "zid_refresh_http_#{status}")
  end

  def save(body)
    tokens = Commerce::Zid::Tokens.credentials(body)
    previous_expiry = @store.credentials['expires_at']
    @store.update!(credentials: @store.credentials.merge(tokens),
                   metadata: @store.metadata.except('refresh_failed_at').merge('token_refreshed_at' => Time.current.iso8601))
    audit('commerce.zid.token_refreshed', expires_at: [previous_expiry, tokens['expires_at']])
    @store.credentials
  rescue Commerce::Error
    raise needs_reauth!('refresh_response_invalid')
  end

  # The tokens stay; the refresh is tried again after RETRY_AFTER. A token that has not expired keeps working meanwhile.
  def retry_later(expired, error)
    @store.update!(metadata: @store.metadata.merge('refresh_failed_at' => Time.current.iso8601)) unless backing_off?
    raise error if expired

    Rails.logger.warn("[Commerce:zid] token refresh deferred store=#{@store.id} code=#{error.code}")
    @store.credentials
  end

  def backing_off?
    failed_at = @store.metadata['refresh_failed_at']
    failed_at.present? && Time.iso8601(failed_at) > RETRY_AFTER.ago
  end

  # The tokens are no longer accepted: they and the cached store data are removed, and an administrator connects the store
  # again (Settings → Commerce → Connect with Zid).
  def needs_reauth!(reason)
    @store.update!(status: :needs_reauth, credentials: @store.credentials.except(*TOKEN_KEYS).presence,
                   metadata: @store.metadata.except('refresh_failed_at'))
    Commerce::Cache.purge(@store)
    audit('commerce.zid.needs_reauth', reason: reason)
    Commerce::Error.new('AUTH_INVALID', reason: reason)
  end

  def audit(event, changes)
    Commerce::AuditTrail.record(event, auditable: @store, changes: changes)
  end
end
