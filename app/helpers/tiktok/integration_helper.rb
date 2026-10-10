module Tiktok::IntegrationHelper
  # Lynomia (docs/p11/00-p10-security-closure.md, SC4). The state token used to carry only
  # `{ sub: account_id, iat: }`, which made it eternal and unbound to a person:
  #
  #   * `verify_expiration: true` does NOT make `exp` mandatory. The jwt gem's expiration verifier returns
  #     early when the payload has no `exp` key (jwt-2.10.3/lib/jwt/claims/expiration.rb:22), so a token
  #     without one passes. Presence is a separate option, `required_claims`, which defaults to [].
  #   * With no `uid`, nothing tied the callback to the person who began the connect flow, and the callback
  #     controller has no authentication of its own, so anyone holding a state token could complete a
  #     connection into the account it names.
  #
  # Both halves are now closed, following the pattern this tree already uses for Shopify
  # (app/helpers/shopify/integration_helper.rb): mint `exp`, and require it on the way back in.
  STATE_TTL = 15.minutes
  REQUIRED_STATE_CLAIMS = %w[exp sub uid].freeze

  # Generates a signed JWT token for Tiktok integration
  #
  # @param account_id [Integer] The account ID to encode in the token
  # @param user_id [Integer] The user beginning the flow; the callback refuses a state naming anyone else
  # @param return_to [String, nil] Optional onboarding return hint
  # @return [String, nil] The encoded JWT token or nil if client secret is missing
  def generate_tiktok_token(account_id, user_id, return_to = nil)
    return if client_secret.blank?

    JWT.encode(token_payload(account_id, user_id, return_to), client_secret, 'HS256')
  rescue StandardError => e
    Rails.logger.error("Failed to generate TikTok token: #{e.message}")
    nil
  end

  # Verifies and decodes a Tiktok JWT token
  #
  # @param token [String] The JWT token to verify
  # @return [Integer, nil] The account ID from the token or nil if invalid
  def verify_tiktok_token(token)
    decoded_tiktok_token(token)&.dig('sub')
  end

  # The user the state was minted for. The callback checks they are still an administrator of the account.
  def tiktok_token_user_id(token)
    decoded_tiktok_token(token)&.dig('uid')
  end

  # Reads the onboarding return hint from a Tiktok JWT token, if present.
  def tiktok_token_return_to(token)
    decoded_tiktok_token(token)&.dig('return_to')
  end

  private

  def client_secret
    @client_secret ||= GlobalConfigService.load('TIKTOK_APP_SECRET', nil)
  end

  # The callback reads three claims off the same state, so memoize the one decode, in the style this file
  # already uses for the secret.
  def decoded_tiktok_token(token)
    return if token.blank? || client_secret.blank?

    @decoded_tiktok_token ||= decode_token(token, client_secret)
  end

  def token_payload(account_id, user_id, return_to = nil)
    issued_at = Time.current.to_i
    payload = { sub: account_id, uid: user_id, iat: issued_at, exp: issued_at + STATE_TTL.to_i }
    payload[:return_to] = return_to if return_to.present?
    payload
  end

  def decode_token(token, secret)
    JWT.decode(token, secret, true, {
                 algorithm: 'HS256',
                 verify_expiration: true,
                 required_claims: REQUIRED_STATE_CLAIMS
               }).first
  rescue StandardError => e
    Rails.logger.error("Unexpected error verifying Tiktok token: #{e.message}")
    nil
  end
end
