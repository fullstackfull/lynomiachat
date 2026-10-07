require 'rails_helper'

RSpec.describe Commerce::Salla::TokenManager do
  include_context 'with commerce encryption'
  include_context 'with salla app'

  let(:account) { create(:account) }
  let(:token_url) { 'https://accounts.salla.sa/oauth2/token' }
  let(:expires_at) { 2.hours.from_now }
  let(:store) do
    create(:commerce_store, :salla, account: account, external_store_id: '1234509876',
                                    credentials: { 'access_token' => 'access-1', 'refresh_token' => 'refresh-1', 'token_type' => 'bearer',
                                                   'scope' => 'offline_access customers.read orders.read shipping.read',
                                                   'access_token_expires_at' => expires_at.utc.iso8601, 'refresh_token_expires_at' => nil })
  end
  let(:refreshed) do
    { access_token: 'access-2', refresh_token: 'refresh-2', token_type: 'bearer', expires: 14.days.from_now.to_i,
      scope: 'offline_access customers.read orders.read shipping.read' }
  end

  def stub_refresh(response = { status: 200, body: refreshed.to_json })
    stub_request(:post, token_url).to_return(response)
  end

  def refresh_requests(refresh_token)
    a_request(:post, token_url).with(body: hash_including('grant_type' => 'refresh_token', 'refresh_token' => refresh_token))
  end

  def error_for
    yield
    nil
  rescue Commerce::Error => e
    e.as_json
  end

  it 'uses a valid access token without refreshing it' do
    store.update!(credentials: store.credentials.merge('access_token_expires_at' => 3.days.from_now.utc.iso8601))
    stub_refresh

    expect(described_class.new(store).access_token).to eq('access-1')
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'refreshes a token that expires within a day, saving both new tokens in one write' do
    stub_refresh

    expect(described_class.new(store).access_token).to eq('access-2')
    expect(refresh_requests('refresh-1').with(body: hash_including('client_id' => 'salla-client-id-for-specs',
                                                                   'client_secret' => salla_client_secret))).to have_been_made.once
    expect(store.reload.credentials).to include('access_token' => 'access-2', 'refresh_token' => 'refresh-2',
                                                'access_token_expires_at' => Time.zone.at(refreshed[:expires]).utc.iso8601)
    expect(store.metadata).not_to have_key('refresh_started_at')
    expect(store).to be_active
  end

  it 'refreshes an expired token' do
    store.update!(credentials: store.credentials.merge('access_token_expires_at' => 1.hour.ago.utc.iso8601))
    stub_refresh

    expect(described_class.new(store).access_token).to eq('access-2')
  end

  it 'keeps the granted scope when the refresh response leaves it out (RFC 6749 §5.1)' do
    stub_refresh(status: 200, body: refreshed.except(:scope).to_json)

    described_class.new(store).access_token

    expect(store.reload.credentials['scope']).to eq('offline_access customers.read orders.read shipping.read')
  end

  it 'sends a refresh token once when ten jobs need a token at the same time' do
    stub_request(:post, token_url).to_return do
      sleep 0.3
      { status: 200, body: refreshed.to_json }
    end

    store_id = store.id
    tokens = Array.new(10) { Thread.new { described_class.new(Commerce::Store.find(store_id)).access_token } }.map(&:value)

    expect(tokens).to all(eq('access-2'))
    expect(a_request(:post, token_url)).to have_been_made.once
  end

  it 'never sends a refresh token again: the next refresh uses the new one' do
    stub_refresh
    described_class.new(store).access_token

    travel(14.days) do
      stub_request(:post, token_url).with(body: hash_including('refresh_token' => 'refresh-2'))
                                    .to_return(status: 200, body: refreshed.merge(access_token: 'access-3', refresh_token: 'refresh-3',
                                                                                  expires: 28.days.from_now.to_i).to_json)
      expect(described_class.new(store.reload).access_token).to eq('access-3')
    end
    expect(refresh_requests('refresh-1')).to have_been_made.once
    expect(refresh_requests('refresh-2')).to have_been_made.once
  end

  describe 'failures' do
    {
      'a rejected refresh token (invalid_grant)' => [{ status: 400, body: '{"error":"invalid_grant"}' }, 'refresh_token_rejected'],
      'a revoked refresh token (401 invalid_grant)' => [{ status: 401, body: '{"error":"invalid_grant"}' }, 'refresh_token_rejected'],
      'a server error, which may have spent the token' => [{ status: 503, body: 'busy' }, 'refresh_http_503'],
      'a success whose tokens cannot be read' => [{ status: 200, body: '{"access_token":"access-2"}' }, 'refresh_response_invalid'],
      'new tokens with a write scope' => [{ status: 200, body: { access_token: 'a', refresh_token: 'r', token_type: 'bearer', expires: 2_000_000_000,
                                                                 scope: 'offline_access orders.read_write customers.read shipping.read' }.to_json },
                                          'refresh_response_invalid']
    }.each do |label, (response, reason)|
      it "needs re-authorization after #{label}, and never sends that refresh token again" do
        stub_refresh(response)

        expect(error_for { described_class.new(store).access_token }).to eq(code: 'AUTH_INVALID', reason: reason)
        expect(store.reload).to be_needs_reauth
        expect(store.credentials).not_to have_key('refresh_token')
        expect(store.metadata).not_to have_key('refresh_started_at')

        expect(error_for { described_class.new(store).access_token }).to eq(code: 'AUTH_INVALID')
        expect(a_request(:post, token_url)).to have_been_made.once
      end
    end

    it 'treats a timeout after sending as a spent refresh token' do
      stub_request(:post, token_url).to_raise(Net::ReadTimeout)

      expect(error_for { described_class.new(store).access_token }).to eq(code: 'AUTH_INVALID', reason: 'refresh_outcome_unknown')
      expect(store.reload).to be_needs_reauth
      expect(store.credentials).not_to have_key('refresh_token')
      expect(a_request(:post, token_url)).to have_been_made.once
    end

    it 'treats a refresh left unfinished by a crashed process as spent, without sending it' do
      store.update!(metadata: store.metadata.merge('refresh_started_at' => 5.minutes.ago.iso8601))
      stub_refresh

      expect(error_for { described_class.new(store).access_token }).to eq(code: 'AUTH_INVALID', reason: 'refresh_interrupted')
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    {
      'a connection that never opened' => [->(stub) { stub.to_timeout }, { code: 'STORE_UNAVAILABLE', reason: 'salla_unreachable' }],
      'rate limiting' => [->(stub) { stub.to_return(status: 429) }, { code: 'RATE_LIMITED' }],
      'our client credentials being rejected' => [->(stub) { stub.to_return(status: 401, body: '{"error":"invalid_client"}') },
                                                  { code: 'STORE_UNAVAILABLE', reason: 'salla_client_rejected' }]
    }.each do |label, (respond, error)|
      it "keeps the refresh token after #{label}, which provably did not use it" do
        respond.call(stub_request(:post, token_url))

        expect(error_for { described_class.new(store).access_token }).to eq(error)
        expect(store.reload).to be_active
        expect(store.credentials['refresh_token']).to eq('refresh-1')
        expect(store.metadata).not_to have_key('refresh_started_at')
      end
    end

    it 'does not start a refresh while the app is not fully configured' do
      InstallationConfig.find_by!(name: 'SALLA_CLIENT_SECRET').update!(value: '')
      GlobalConfig.clear_cache

      expect { described_class.new(store).access_token }.to raise_error(KeyError)
      expect(store.reload.metadata).not_to have_key('refresh_started_at')
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it 'refuses a store that needs re-authorization, without calling Salla' do
      store.update!(status: :needs_reauth)

      expect(error_for { described_class.new(store).access_token }).to eq(code: 'AUTH_INVALID')
      expect(a_request(:post, token_url)).not_to have_been_made
    end
  end

  it 'audits refreshes and re-authorization needs without any token or secret' do
    stub_refresh
    described_class.new(store).access_token
    travel(14.days) do
      stub_refresh(status: 400, body: '{"error":"invalid_grant"}')
      error_for { described_class.new(store.reload).access_token }
    end

    logs = Custom::AuditLog.where(auditable: store).order(:id)
    expect(logs.pluck(:comment)).to eq(%w[commerce.salla.token_refreshed commerce.salla.needs_reauth])
    expect(logs.to_json).not_to include('access-1', 'refresh-1', 'access-2', 'refresh-2', salla_client_secret)
  end

  it 'keeps tokens and the client secret out of logs and errors' do
    stub_refresh(status: 400, body: '{"error":"invalid_grant","error_description":"refresh-1 is not valid"}')
    logged = []
    allow(Rails.logger).to receive(:info) { |message| logged << message }

    error = error_for { described_class.new(store).access_token }

    expect([logged.join, error.to_json].join).not_to include('access-1', 'refresh-1', salla_client_secret)
  end
end
