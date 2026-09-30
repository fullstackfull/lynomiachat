# The OAuth `state` of a Zid authorization (docs/commerce/14-zid-oauth-and-tokens.md §state). Zid's callback names no
# Lynomia account, so the account and the administrator come only from this state, never from other query parameters:
#
# - signed with a key derived from the app's secret_key_base (Rails message verifier, purpose-bound), valid for TTL;
# - bound to one account and one user, both re-checked at the callback;
# - carrying a nonce stored in Redis and deleted on first use, so a state is accepted once;
# - bound to the browser that started it: the nonce is also in an encrypted HttpOnly cookie, and the callback compares it.
module Commerce::Zid::OauthState
  TTL = 10.minutes
  PURPOSE = 'commerce_zid_oauth'.freeze

  Issued = Data.define(:state, :nonce)

  def self.issue(account:, user:)
    nonce = SecureRandom.urlsafe_base64(32)
    Redis::Alfred.set(key(nonce), 1, ex: TTL.to_i)
    state = verifier.generate({ 'nonce' => nonce, 'account_id' => account.id, 'user_id' => user.id }, purpose: PURPOSE, expires_in: TTL)
    Issued.new(state: state, nonce: nonce)
  end

  # { 'account_id' =>, 'user_id' => } for a valid state, presented once, by the browser that started it; nil otherwise.
  def self.consume(state, browser_nonce)
    data = verifier.verified(state.to_s, purpose: PURPOSE)
    return unless data.is_a?(Hash) && browser_nonce.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(data['nonce'].to_s, browser_nonce)
    return unless Redis::Alfred.delete(key(data['nonce'])) == 1

    data.slice('account_id', 'user_id')
  end

  def self.key(nonce) = "COMMERCE::ZID::OAUTH_STATE::#{Digest::SHA256.hexdigest(nonce)}"

  def self.verifier = Rails.application.message_verifier(PURPOSE)

  private_class_method :key, :verifier
end
