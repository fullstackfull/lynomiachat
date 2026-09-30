require 'rails_helper'

RSpec.describe Commerce::Shopify::Tokens do
  let(:now) { Time.zone.parse('2026-09-30T10:00:00Z') }
  let(:body) { JSON.parse(file_fixture('commerce/shopify/token.json').read) }

  it "stores the expiring offline token with the expiry times computed from Shopify's own values" do
    expect(described_class.credentials(body, now: now)).to eq(
      'access_token' => 'shpat_fixture_access_token_0001', 'access_token_expires_at' => '2026-09-30T11:00:00Z',
      'refresh_token' => 'shprt_fixture_refresh_token_0001', 'refresh_token_expires_at' => '2026-12-29T10:00:00Z',
      'scope' => 'read_customers,read_orders'
    )
  end

  it 'never assumes a lifetime: other values from Shopify give other expiry times' do
    credentials = described_class.credentials(body.merge('expires_in' => 120, 'refresh_token_expires_in' => 600), now: now)

    expect(credentials.values_at('access_token_expires_at', 'refresh_token_expires_at')).to eq(%w[2026-09-30T10:02:00Z 2026-09-30T10:10:00Z])
  end

  it 'refuses a non-expiring token, an online token and malformed answers' do
    online = body.except('refresh_token', 'refresh_token_expires_in').merge('associated_user' => { 'id' => 1 })
    [
      body.except('refresh_token', 'expires_in', 'refresh_token_expires_in'),
      online,
      body.merge('associated_user' => { 'id' => 1 }),
      body.merge('expires_in' => '3600'),
      body.merge('refresh_token_expires_in' => 0),
      body.merge('access_token' => ''),
      body.except('scope'),
      'not json', nil
    ].each do |answer|
      expect { described_class.credentials(answer, now: now) }.to raise_error(Commerce::Error, 'INVALID_RESPONSE: shopify_tokens')
    end
  end
end
