# The OAuth `state` of a provider authorization started from Lynomia (Zid, Shopify; docs/commerce/14-zid-oauth-and-tokens.md
# §state, 18-shopify-oauth-and-tokens.md). The provider's callback names no Lynomia account, so the account and the
# administrator come only from this state, never from other query parameters:
#
# - signed with a key derived from the app's secret_key_base (Rails message verifier, purpose-bound per provider), valid
#   for TTL, so one provider's state is never accepted by another provider's callback;
# - bound to one account and one user, both re-checked at the callback, and to any further `claims` the callback must
#   match (the Shopify shop the administrator entered);
# - carrying a nonce stored in Redis and deleted on first use, so a state is accepted once;
# - bound to the browser that started it: the nonce is also in an encrypted HttpOnly cookie, and the callback compares it.
module Commerce::OauthState
  TTL = 10.minutes

  Issued = Data.define(:state, :nonce)

  def self.issue(provider, account:, user:, **claims)
    nonce = SecureRandom.urlsafe_base64(32)
    Redis::Alfred.set(key(provider, nonce), 1, ex: TTL.to_i)
    payload = claims.stringify_keys.merge('nonce' => nonce, 'account_id' => account.id, 'user_id' => user.id)
    Issued.new(state: verifier(provider).generate(payload, purpose: purpose(provider), expires_in: TTL), nonce: nonce)
  end

  # { 'account_id' =>, 'user_id' =>, claims… } for a valid state, presented once, by the browser that started it; nil
  # otherwise.
  def self.consume(provider, state, browser_nonce)
    data = verifier(provider).verified(state.to_s, purpose: purpose(provider))
    return unless data.is_a?(Hash) && browser_nonce.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(data['nonce'].to_s, browser_nonce)
    return unless Redis::Alfred.delete(key(provider, data['nonce'])) == 1

    data.except('nonce')
  end

  def self.key(provider, nonce) = "COMMERCE::#{provider.upcase}::OAUTH_STATE::#{Digest::SHA256.hexdigest(nonce)}"

  def self.purpose(provider) = "commerce_#{provider}_oauth"

  def self.verifier(provider) = Rails.application.message_verifier(purpose(provider))

  private_class_method :key, :purpose, :verifier
end
