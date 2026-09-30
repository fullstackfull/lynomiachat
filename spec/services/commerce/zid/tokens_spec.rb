require 'rails_helper'

RSpec.describe Commerce::Zid::Tokens do
  let(:now) { Time.zone.parse('2026-09-30 12:00:00 UTC') }
  let(:body) { JSON.parse(file_fixture('commerce/zid/token.json').read) }

  it 'keeps the two tokens apart and stores the expiry Zid states' do
    expect(described_class.credentials(body, now: now)).to eq(
      'authorization' => 'zid-fixture-authorization-token', 'access_token' => 'zid-fixture-manager-token',
      'refresh_token' => 'zid-fixture-refresh-token', 'token_type' => 'Bearer', 'expires_at' => '2027-09-30T12:00:00Z'
    )
  end

  it 'accepts the capitalised Authorization key and a numeric string lifetime' do
    body['Authorization'] = body.delete('authorization')
    body['expires_in'] = '3600'

    expect(described_class.credentials(body, now: now)).to include('authorization' => 'zid-fixture-authorization-token',
                                                                   'expires_at' => '2026-09-30T13:00:00Z')
  end

  it 'invents nothing Zid did not send: no expiry, token type or scope' do
    credentials = described_class.credentials(body.except('expires_in', 'token_type'), now: now)

    expect(credentials).to include('expires_at' => nil)
    expect(credentials.keys).not_to include('token_type', 'scope', 'refresh_token_expires_at')
  end

  it 'refuses a response without both tokens and a refresh token' do
    %w[authorization access_token refresh_token].each do |name|
      expect { described_class.credentials(body.except(name)) }.to raise_error(Commerce::Error, 'INVALID_RESPONSE: zid_tokens')
    end
    expect { described_class.credentials('not json') }.to raise_error(Commerce::Error, 'INVALID_RESPONSE: zid_tokens')
  end
end
