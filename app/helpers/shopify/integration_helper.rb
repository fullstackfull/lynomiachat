module Shopify::IntegrationHelper
  REQUIRED_SCOPES = %w[read_customers read_orders read_fulfillments].freeze

  STATE_TTL = 10.minutes

  # Generates the signed OAuth state for a Shopify install: bound to the account and to the shop it was started for,
  # and valid for STATE_TTL only.
  #
  # @param account_id [Integer] The account ID to encode in the token
  # @param shop [String] The *.myshopify.com domain the authorization was started for
  # @return [String, nil] The encoded JWT token or nil if client secret is missing
  def generate_shopify_token(account_id, shop)
    return if client_secret.blank?

    JWT.encode(token_payload(account_id, shop), client_secret, 'HS256')
  rescue StandardError => e
    Rails.logger.error("Failed to generate Shopify token: #{e.message}")
    nil
  end

  def token_payload(account_id, shop)
    issued_at = Time.current.to_i
    {
      sub: account_id,
      shop: Shopify::ShopDomain.normalize(shop),
      iat: issued_at,
      exp: issued_at + STATE_TTL.to_i
    }
  end

  # Verifies a Shopify OAuth state: signature, expiry, and that it was issued for this shop.
  #
  # @param token [String] The JWT token to verify
  # @param shop [String] The shop domain Shopify redirected back with
  # @return [Integer, nil] The account ID from the token or nil if invalid
  def verify_shopify_token(token, shop)
    return if token.blank? || client_secret.blank?

    payload = decode_token(token, client_secret)
    return if payload.blank? || payload['shop'] != Shopify::ShopDomain.normalize(shop)

    payload['sub']
  end

  private

  def client_id
    @client_id ||= GlobalConfigService.load('SHOPIFY_CLIENT_ID', nil)
  end

  def client_secret
    @client_secret ||= GlobalConfigService.load('SHOPIFY_CLIENT_SECRET', nil)
  end

  def decode_token(token, secret)
    JWT.decode(
      token,
      secret,
      true,
      {
        algorithm: 'HS256',
        verify_expiration: true,
        required_claims: %w[exp shop]
      }
    ).first
  rescue StandardError => e
    Rails.logger.error("Unexpected error verifying Shopify token: #{e.message}")
    nil
  end
end
