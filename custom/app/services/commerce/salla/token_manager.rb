# Keeps a Salla store's access token usable (docs/commerce/11-salla-auth-and-token-lifecycle.md).
#
# Salla refresh tokens are single-use: sending one twice revokes the whole token chain. So a refresh:
#   1. runs only under the merchant's lock (Commerce::Salla::MerchantLock), after re-reading the store, since another
#      process may have just refreshed it;
#   2. saves `refresh_started_at` on the store before the request, and sends the request once, without retries;
#   3. saves both new tokens in one write, then releases the lock.
# If the request may have reached Salla but its answer was lost (a timeout after sending, a 5xx, a crash that left
# `refresh_started_at` behind), the old refresh token may already be spent. It is never sent again: it is removed and the
# store needs re-authorization. Only failures that provably left it unused (not sent, rate limited, our client
# credentials rejected) are retried on a later read.
class Commerce::Salla::TokenManager
  REFRESH_BEFORE = 1.day

  def initialize(store)
    @store = store
  end

  # A usable access token, refreshed first when it expires within a day.
  def access_token
    return @store.credentials['access_token'] if usable?

    Commerce::Salla::MerchantLock.with(@store.external_store_id) do
      @store.reload
      usable? ? @store.credentials['access_token'] : refresh
    end
  end

  private

  def usable?
    raise Commerce::Error, 'AUTH_INVALID' if @store.needs_reauth? || @store.credentials.blank?

    Time.iso8601(@store.credentials['access_token_expires_at']) > REFRESH_BEFORE.from_now
  end

  def refresh
    raise needs_reauth!('refresh_interrupted') if @store.metadata['refresh_started_at']

    client = { client_id: Commerce::Salla::Config.client_id, client_secret: Commerce::Salla::Config.client_secret }
    @store.update!(metadata: @store.metadata.merge('refresh_started_at' => Time.current.iso8601))
    status, body = request(client)
    return save(body) if status == 200

    raise failure(status, body.is_a?(Hash) ? body['error'] : nil)
  end

  # Only a 429 and a rejected client provably left the refresh token unused.
  def failure(status, oauth_error)
    return unused!('RATE_LIMITED', nil) if status == 429
    return unused!('STORE_UNAVAILABLE', 'salla_client_rejected') if status == 401 && oauth_error == 'invalid_client'

    needs_reauth!(oauth_error == 'invalid_grant' ? 'refresh_token_rejected' : "refresh_http_#{status}")
  end

  def request(client)
    Commerce::Salla::Oauth.refresh(@store.credentials['refresh_token'], **client)
  rescue Commerce::Error => e
    raise unused!('STORE_UNAVAILABLE', 'salla_unreachable') if e.reason == 'not_sent'

    raise needs_reauth!('refresh_outcome_unknown')
  end

  def save(body)
    credentials = Commerce::Salla::Tokens.credentials(body.is_a?(Hash) ? body.reverse_merge('scope' => @store.credentials['scope']) : {})
    previous_expiry = @store.credentials['access_token_expires_at']
    @store.update!(credentials: credentials,
                   metadata: @store.metadata.except('refresh_started_at').merge('token_refreshed_at' => Time.current.iso8601))
    Commerce::AuditTrail.record('commerce.salla.token_refreshed',
                                auditable: @store, changes: { access_token_expires_at: [previous_expiry, credentials['access_token_expires_at']] })
    credentials['access_token']
  rescue Commerce::Error
    # Salla accepted the refresh token, so it is spent, but the answer cannot be used.
    raise needs_reauth!('refresh_response_invalid')
  end

  # The request provably did not use the refresh token: it stays, and a later read tries again.
  def unused!(code, reason)
    @store.update!(metadata: @store.metadata.except('refresh_started_at'))
    Commerce::Error.new(code, reason: reason)
  end

  # The refresh token is, or may be, spent. It is removed so it can never be sent again, and an administrator has to
  # re-authorize the app (reinstall or update it in Salla). Cached store data is dropped with it.
  def needs_reauth!(reason)
    @store.update!(status: :needs_reauth, credentials: @store.credentials.except('refresh_token'),
                   metadata: @store.metadata.except('refresh_started_at'))
    Commerce::Cache.purge(@store)
    Commerce::AuditTrail.record('commerce.salla.needs_reauth', auditable: @store, changes: { reason: reason })
    Commerce::Error.new('AUTH_INVALID', reason: reason)
  end
end
