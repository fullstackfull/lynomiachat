# frozen_string_literal: true

require 'net/http'

# Verifies Google / Apple ID tokens (JWT) sent by the mobile app.
#
# Always checked:
#   - signature (provider public keys) -> the token can't be forged
#   - expiry                           -> a token is valid ~1 hour only
#   - issuer                           -> really issued by Google / Apple
#
# Checked only when configured (ENV, comma separated):
#   - audience = the token was issued for OUR app
#     MOBILE_GOOGLE_CLIENT_IDS  Web + Android + iOS OAuth client IDs of the app
#     MOBILE_APPLE_CLIENT_IDS   iOS bundle ID (+ Services ID if Apple sign-in is used on Android)
#
# Until the IDs are set, tokens issued for other apps are also accepted
# (a warning is logged on every sign-in). Set them as soon as possible.
class MobileAuth::TokenVerifier
  class InvalidToken < StandardError; end
  # Kept for the controller's rescue list (no longer raised)
  class NotConfigured < StandardError; end

  PROVIDERS = {
    'google' => {
      jwks_url: 'https://www.googleapis.com/oauth2/v3/certs',
      issuers: %w[accounts.google.com https://accounts.google.com],
      client_ids_env: 'MOBILE_GOOGLE_CLIENT_IDS'
    },
    'apple' => {
      jwks_url: 'https://appleid.apple.com/auth/keys',
      issuers: %w[https://appleid.apple.com],
      client_ids_env: 'MOBILE_APPLE_CLIENT_IDS'
    }
  }.freeze

  def initialize(provider)
    @provider = provider
    @config = PROVIDERS.fetch(provider)
  end

  # Returns { uid:, email:, email_verified:, name: }
  def verify(token)
    raise InvalidToken, 'Token is missing' if token.blank?

    payload, = JWT.decode(token, nil, true, decode_options)

    {
      uid: payload['sub'],
      email: payload['email']&.downcase,
      email_verified: ActiveModel::Type::Boolean.new.cast(payload['email_verified']) || false,
      name: payload['name']
    }
  rescue JWT::DecodeError => e
    raise InvalidToken, e.message
  end

  private

  def decode_options
    options = {
      algorithms: ['RS256'],
      jwks: jwks_loader,
      iss: @config[:issuers],
      verify_iss: true
    }

    if client_ids.any?
      options.merge(aud: client_ids, verify_aud: true)
    else
      Rails.logger.warn("[MobileAuth] #{@config[:client_ids_env]} is not set: " \
                        "#{@provider} tokens are accepted without checking they were issued for this app")
      options.merge(verify_aud: false)
    end
  end

  def client_ids
    @client_ids ||= ENV.fetch(@config[:client_ids_env], '').split(',').map(&:strip).compact_blank
  end

  def cache_key
    "mobile_auth:jwks:#{@provider}"
  end

  # Keys are cached for 6 hours and refreshed when the provider rotates them
  def jwks_loader
    lambda do |options|
      Rails.cache.delete(cache_key) if options[:kid_not_found] || options[:invalidate]
      Rails.cache.fetch(cache_key, expires_in: 6.hours) { fetch_keys }
    end
  end

  def fetch_keys
    response = Net::HTTP.get_response(URI(@config[:jwks_url]))
    raise InvalidToken, "Could not load #{@provider} keys" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body, symbolize_names: true)
  end
end
