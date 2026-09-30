require 'rails_helper'

RSpec.describe Commerce::Zid::TokenManager do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:token_url) { 'https://oauth.zid.sa/oauth/token' }
  let(:expires_at) { 30.days.from_now }
  let(:store) do
    create(:commerce_store, :zid, account: account, external_store_id: '318001',
                                  credentials: { 'authorization' => 'auth-1', 'access_token' => 'manager-1', 'refresh_token' => 'refresh-1',
                                                 'token_type' => 'Bearer', 'expires_at' => expires_at.utc.iso8601,
                                                 'webhook_username' => 'hook-user', 'webhook_password' => 'hook-password' })
  end
  let(:refreshed) do
    { access_token: 'manager-2', authorization: 'auth-2', refresh_token: 'refresh-2', token_type: 'Bearer', expires_in: 31_536_000 }.to_json
  end
  let(:refresh_request) { a_request(:post, token_url).with(body: hash_including('grant_type' => 'refresh_token', 'refresh_token' => 'refresh-1')) }
  let(:manager_token) { ->(credentials) { credentials['access_token'] } }

  def error_for
    yield
    nil
  rescue Commerce::Error => e
    e.as_json
  end

  it 'uses valid tokens without refreshing them' do
    store.update!(credentials: store.credentials.merge('expires_at' => 200.days.from_now.utc.iso8601))
    stub_request(:post, token_url).to_return(status: 200, body: refreshed)

    expect(described_class.new(store).with_credentials(&manager_token)).to eq('manager-1')
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'refreshes tokens within 60 days of their expiry, saving them in one write and keeping the webhook credentials' do
    stub_request(:post, token_url).to_return(status: 200, body: refreshed)

    expect(described_class.new(store).with_credentials(&manager_token)).to eq('manager-2')
    expect(refresh_request.with(body: hash_including('client_id' => '4821', 'client_secret' => zid_client_secret,
                                                     'redirect_uri' => 'https://app.lynomia.test/commerce/zid/callback'))).to have_been_made.once
    expect(store.reload.credentials).to include('authorization' => 'auth-2', 'access_token' => 'manager-2', 'refresh_token' => 'refresh-2',
                                                'webhook_username' => 'hook-user', 'webhook_password' => 'hook-password')
    expect(Time.iso8601(store.credentials['expires_at'])).to be > 360.days.from_now
  end

  it 'refreshes expired tokens' do
    store.update!(credentials: store.credentials.merge('expires_at' => 1.minute.ago.utc.iso8601))
    stub_request(:post, token_url).to_return(status: 200, body: refreshed)

    expect(described_class.new(store).with_credentials(&manager_token)).to eq('manager-2')
  end

  it 'sends one refresh when ten jobs need tokens at the same time' do
    stub_request(:post, token_url).to_return do
      sleep 0.3
      { status: 200, body: refreshed }
    end

    store_id = store.id
    tokens = Array.new(10) { Thread.new { described_class.new(Commerce::Store.find(store_id)).with_credentials(&manager_token) } }.map(&:value)

    expect(tokens).to all(eq('manager-2'))
    expect(a_request(:post, token_url)).to have_been_made.once
  end

  it 'moves the store to needs_reauth when Zid refuses the refresh token, removing the tokens and cached data' do
    stub_request(:post, token_url).to_return(status: 400, body: '{"error":"invalid_grant"}')
    Redis::Alfred.set("COMMERCE::V1::ACCOUNT::#{account.id}::STORE::#{store.id}::ORDERS::x", '{}')

    expect(error_for { described_class.new(store).with_credentials(&manager_token) }).to eq(code: 'AUTH_INVALID', reason: 'refresh_token_rejected')
    expect(store.reload).to be_needs_reauth
    expect(store.credentials).to eq('webhook_username' => 'hook-user', 'webhook_password' => 'hook-password')
    expect(Redis::Alfred.get("COMMERCE::V1::ACCOUNT::#{account.id}::STORE::#{store.id}::ORDERS::x")).to be_nil
    expect(error_for { described_class.new(store).with_credentials(&manager_token) }).to eq(code: 'AUTH_INVALID')
    expect(a_request(:post, token_url)).to have_been_made.once
  end

  it 'treats a revoked authorization (401) the same way' do
    stub_request(:post, token_url).to_return(status: 401, body: '{"error":"invalid_request","message":"The refresh token is invalid."}')

    expect(error_for { described_class.new(store).with_credentials(&manager_token) }).to eq(code: 'AUTH_INVALID', reason: 'refresh_token_rejected')
    expect(store.reload).to be_needs_reauth
  end

  it 'fails safely on a malformed refresh answer, without trying again' do
    stub_request(:post, token_url).to_return(status: 200, body: '{"access_token":"manager-2"}')

    expect(error_for { described_class.new(store).with_credentials(&manager_token) }).to eq(code: 'AUTH_INVALID', reason: 'refresh_response_invalid')
    expect(store.reload).to be_needs_reauth
    expect(store.credentials.to_json).not_to include('manager-2')
  end

  it 'does not assume single-use refresh tokens: a failed refresh keeps them and waits an hour before trying again' do
    stub_request(:post, token_url).to_return(status: 503).then.to_return(status: 200, body: refreshed)

    expect(described_class.new(store).with_credentials(&manager_token)).to eq('manager-1')
    expect(described_class.new(store.reload).with_credentials(&manager_token)).to eq('manager-1')
    expect(store.credentials['refresh_token']).to eq('refresh-1')
    expect(a_request(:post, token_url)).to have_been_made.once

    travel(61.minutes) do
      expect(described_class.new(store.reload).with_credentials(&manager_token)).to eq('manager-2')
    end
    expect(a_request(:post, token_url)).to have_been_made.twice
  end

  it 'reports an expired token whose refresh failed, without retrying it until the hour has passed' do
    store.update!(credentials: store.credentials.merge('expires_at' => 1.minute.ago.utc.iso8601))
    stub_request(:post, token_url).to_raise(Net::ReadTimeout)

    expect(error_for { described_class.new(store).with_credentials(&manager_token) }).to eq(code: 'TIMEOUT', reason: 'unknown_outcome')
    expect(error_for { described_class.new(store.reload).with_credentials(&manager_token) })
      .to eq(code: 'STORE_UNAVAILABLE', reason: 'zid_refresh_backoff')
    expect(store.reload).to be_active
    expect(store.credentials['refresh_token']).to eq('refresh-1')
    expect(a_request(:post, token_url)).to have_been_made.once
  end

  describe 'when Zid rejects the tokens before their expiry' do
    before { store.update!(credentials: store.credentials.merge('expires_at' => 200.days.from_now.utc.iso8601)) }

    let(:calls) { [] }
    let(:api) do
      lambda do |credentials|
        calls << credentials['access_token']
        raise Commerce::Error, 'AUTH_INVALID' if credentials['access_token'] == 'manager-1'

        credentials['access_token']
      end
    end

    it 'refreshes once and retries once' do
      stub_request(:post, token_url).to_return(status: 200, body: refreshed)

      expect(described_class.new(store).with_credentials(&api)).to eq('manager-2')
      expect(calls).to eq(%w[manager-1 manager-2])
    end

    it 'uses tokens another process refreshed meanwhile instead of refreshing again' do
      stale = store.credentials
      store.update!(credentials: stale.merge('access_token' => 'manager-3', 'authorization' => 'auth-3'))
      manager = described_class.new(Commerce::Store.find(store.id))
      allow(manager).to receive(:credentials).and_return(stale)

      expect(manager.with_credentials(&api)).to eq('manager-3')
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it 'moves the store to needs_reauth when the refreshed tokens are rejected too' do
      stub_request(:post, token_url).to_return(status: 200, body: refreshed)

      error = error_for { described_class.new(store).with_credentials { raise Commerce::Error, 'AUTH_INVALID' } }

      expect(error).to eq(code: 'AUTH_INVALID', reason: 'tokens_rejected')
      expect(store.reload).to be_needs_reauth
    end

    it 'never falls back to cached data while the refresh has to wait' do
      stub_request(:post, token_url).to_return(status: 503)

      expect(error_for { described_class.new(store).with_credentials(&api) }).to eq(code: 'AUTH_INVALID', reason: 'zid_refresh_pending')
      expect(store.reload).to be_active
    end
  end

  it 'only refreshes tokens without a known expiry after Zid rejects them' do
    store.update!(credentials: store.credentials.merge('expires_at' => nil))
    stub_request(:post, token_url).to_return(status: 200, body: refreshed)

    expect(described_class.new(store).with_credentials(&manager_token)).to eq('manager-1')
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'refuses a store that needs re-authorization, without calling Zid' do
    store.update!(status: :needs_reauth)

    expect(error_for { described_class.new(store).with_credentials(&manager_token) }).to eq(code: 'AUTH_INVALID')
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'keeps tokens and the client secret out of logs, errors and the audit log' do
    stub_request(:post, token_url).to_return(status: 200, body: refreshed).then
                                  .to_return(status: 400, body: '{"error":"invalid_grant","message":"refresh-2 is not valid"}')
    logged = []
    allow(Rails.logger).to receive(:info) { |message| logged << message }
    allow(Rails.logger).to receive(:warn) { |message| logged << message }

    described_class.new(store).with_credentials(&manager_token)
    error = travel(330.days) { error_for { described_class.new(store.reload).with_credentials(&manager_token) } }

    audit = defined?(Enterprise::AuditLog) ? Enterprise::AuditLog.where(auditable: store).order(:id) : []
    expect(audit.map(&:comment)).to eq(%w[commerce.zid.token_refreshed commerce.zid.needs_reauth]) if defined?(Enterprise::AuditLog)
    everything = [logged.join, error.to_json, audit.to_json].join
    %w[auth-1 manager-1 refresh-1 auth-2 manager-2 refresh-2 hook-password].push(zid_client_secret).each do |secret|
      expect(everything).not_to include(secret)
    end
  end
end
