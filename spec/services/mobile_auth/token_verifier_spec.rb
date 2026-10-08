require 'rails_helper'

# The audience check is the control that stops a provider token minted for another app being replayed at this one.
# These examples pin that it cannot be turned off by leaving an environment variable unset.
RSpec.describe MobileAuth::TokenVerifier do
  let(:key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk) { JWT::JWK.new(key, { kid: 'test-kid', use: 'sig', alg: 'RS256' }) }
  let(:ours) { 'ours.apps.googleusercontent.com' }
  let(:claims) { { 'sub' => 'google-uid-1', 'email' => 'Person@Example.com', 'email_verified' => true, 'name' => 'Person' } }

  def token_for(audience)
    payload = claims.merge('iss' => 'https://accounts.google.com', 'aud' => audience, 'exp' => 1.hour.from_now.to_i)
    JWT.encode(payload, key, 'RS256', { kid: jwk[:kid] })
  end

  before do
    stub_request(:get, 'https://www.googleapis.com/oauth2/v3/certs').to_return(
      status: 200, body: JWT::JWK::Set.new(jwk).export.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  describe '#verify' do
    it 'accepts a token issued for one of the configured client ids' do
      with_modified_env MOBILE_GOOGLE_CLIENT_IDS: "other.example.com, #{ours}" do
        expect(described_class.new('google').verify(token_for(ours)))
          .to include(uid: 'google-uid-1', email: 'person@example.com', email_verified: true)
      end
    end

    it 'rejects a token minted for a different app' do
      with_modified_env MOBILE_GOOGLE_CLIENT_IDS: ours do
        expect { described_class.new('google').verify(token_for('attacker.apps.googleusercontent.com')) }
          .to raise_error(described_class::InvalidToken)
      end
    end

    it 'refuses to verify at all when the client ids are not configured' do
      with_modified_env MOBILE_GOOGLE_CLIENT_IDS: nil do
        expect { described_class.new('google').verify(token_for(ours)) }
          .to raise_error(described_class::NotConfigured, /MOBILE_GOOGLE_CLIENT_IDS/)
      end
    end

    it 'treats a blank client id list the same as an unset one' do
      with_modified_env MOBILE_GOOGLE_CLIENT_IDS: ' , ' do
        expect { described_class.new('google').verify(token_for(ours)) }.to raise_error(described_class::NotConfigured)
      end
    end

    it 'refuses Apple sign-in when its own client ids are not configured' do
      with_modified_env MOBILE_APPLE_CLIENT_IDS: nil do
        expect { described_class.new('apple').verify('a.b.c') }
          .to raise_error(described_class::NotConfigured, /MOBILE_APPLE_CLIENT_IDS/)
      end
    end

    it 'rejects a missing token before anything else' do
      expect { described_class.new('google').verify(nil) }.to raise_error(described_class::InvalidToken, 'Token is missing')
    end
  end
end
