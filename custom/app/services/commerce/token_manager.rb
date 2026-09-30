# Keeps the OAuth tokens of a store authorized from Lynomia usable: the lifecycle Zid and Shopify share
# (docs/commerce/14-zid-oauth-and-tokens.md §lifecycle, 18-shopify-oauth-and-tokens.md §refresh). Each provider's
# subclass says when its tokens are due, how a refresh is sent and which failures leave the tokens in place.
#
# Tokens are refreshed shortly before they expire, and when the provider rejects them earlier (AUTH_INVALID): one refresh
# and one retry, then the merchant authorizes again. A refresh is never sent twice at once:
#   1. it runs only under the store's lock (Commerce::StoreLock), after re-reading the store, since another process may
#      have just refreshed it: concurrent readers wait, then use the new tokens;
#   2. the new tokens are saved in one write.
# A refresh that fails for a reason that can pass (the provider unavailable or rate limited, an answer lost in transit)
# keeps the tokens, and no refresh is tried again for the subclass's RETRY_AFTER; meanwhile a token that has not expired
# is still used. The provider refusing the refresh token (revoked by an uninstall, expired) moves the store to
# needs_reauth: its tokens and cached data are removed and an administrator connects it again.
class Commerce::TokenManager
  def initialize(store)
    @store = store
  end

  # Runs the block with usable credentials. When the provider rejects them (AUTH_INVALID), they are refreshed once and the
  # block runs once more; rejected again, the authorization is gone and the store needs re-authorization.
  def with_credentials(&)
    current = credentials
    yield current
  rescue Commerce::Error => e
    raise unless e.code == 'AUTH_INVALID' && current

    retry_with(renew(current), &)
  end

  # The stored credentials, refreshed first when they are due.
  def credentials
    return authorized_credentials unless refresh_due?

    Commerce::StoreLock.with(provider, @store.external_store_id) do
      @store.reload
      refresh_due? ? refresh(expired: expired?) : authorized_credentials
    end
  end

  private

  # After the provider rejected `rejected`: the tokens another process saved meanwhile, or one refresh here. Until a
  # refresh succeeds the error stays AUTH_INVALID, so nothing cached is served over tokens the provider refused.
  def renew(rejected)
    Commerce::StoreLock.with(provider, @store.external_store_id) do
      @store.reload
      authorized_credentials['access_token'] == rejected['access_token'] ? refresh(expired: true) : @store.credentials
    end
  rescue Commerce::Error => e
    raise if e.code == 'AUTH_INVALID'

    raise Commerce::Error.new('AUTH_INVALID', reason: "#{provider}_refresh_pending")
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

  # `expired`: the current token cannot be used any more, so a refresh that has to wait is an error, not a later retry.
  def refresh(expired:)
    outcome = backing_off? ? Commerce::Error.new('STORE_UNAVAILABLE', reason: "#{provider}_refresh_backoff") : request_refresh
    outcome.is_a?(Commerce::Error) ? retry_later(expired, outcome) : outcome
  end

  # A refresh the provider did not answer with 200: needs_reauth when it refused the refresh token, else the error of a
  # refresh that can be tried again later.
  def failure(status, body)
    oauth_error = body.is_a?(Hash) ? body['error'] : nil
    return Commerce::Error.new('RATE_LIMITED') if status == 429
    return Commerce::Error.new('STORE_UNAVAILABLE', reason: "#{provider}_client_rejected") if oauth_error == 'invalid_client'
    raise needs_reauth!('refresh_token_rejected') if [400, 401].include?(status)

    Commerce::Error.new('STORE_UNAVAILABLE', reason: "#{provider}_refresh_http_#{status}")
  end

  def save(tokens, expiry_key)
    previous_expiry = @store.credentials[expiry_key]
    @store.update!(credentials: @store.credentials.merge(tokens),
                   metadata: @store.metadata.except('refresh_failed_at').merge('token_refreshed_at' => Time.current.iso8601))
    audit("commerce.#{provider}.token_refreshed", expiry_key => [previous_expiry, tokens[expiry_key]])
    @store.credentials
  end

  # The tokens stay; the refresh is tried again after RETRY_AFTER. A token that has not expired keeps working meanwhile.
  def retry_later(expired, error)
    @store.update!(metadata: @store.metadata.merge('refresh_failed_at' => Time.current.iso8601)) unless backing_off?
    raise error if expired

    Rails.logger.warn("[Commerce:#{provider}] token refresh deferred store=#{@store.id} code=#{error.code}")
    @store.credentials
  end

  def backing_off?
    failed_at = @store.metadata['refresh_failed_at']
    failed_at.present? && Time.iso8601(failed_at) > self.class::RETRY_AFTER.ago
  end

  # The tokens are no longer accepted: they and the cached store data are removed, and an administrator connects the store
  # again (Settings → Commerce).
  def needs_reauth!(reason)
    @store.update!(status: :needs_reauth, credentials: @store.credentials.except(*self.class::TOKEN_KEYS).presence,
                   metadata: @store.metadata.except('refresh_failed_at'))
    Commerce::Cache.purge(@store)
    audit("commerce.#{provider}.needs_reauth", reason: reason)
    Commerce::Error.new('AUTH_INVALID', reason: reason)
  end

  def audit(event, changes)
    Commerce::AuditTrail.record(event, auditable: @store, changes: changes)
  end

  def provider = @store.provider
end
