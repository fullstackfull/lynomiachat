require 'rails_helper'

RSpec.describe Commerce::Shopify::TokenManager do
  include_context 'with commerce encryption'
  include_context 'with shopify commerce app'

  let(:account) { create(:account) }
  let(:token_url) { 'https://lynomia-demo.myshopify.com/admin/oauth/access_token' }
  let(:access_expires_at) { 2.minutes.from_now }
  let(:store) do
    create(:commerce_store, :shopify, account: account, external_store_id: '68210001', base_url: 'https://lynomia-demo.myshopify.com',
                                      credentials: { 'access_token' => 'access-1', 'access_token_expires_at' => access_expires_at.utc.iso8601,
                                                     'refresh_token' => 'refresh-1', 'refresh_token_expires_at' => 60.days.from_now.utc.iso8601,
                                                     'scope' => 'read_customers,read_orders' })
  end
  let(:refreshed) do
    { access_token: 'access-2', refresh_token: 'refresh-2', scope: 'read_customers,read_orders', expires_in: 3600,
      refresh_token_expires_in: 7_776_000 }.to_json
  end
  let(:refresh_request) do
    a_request(:post, token_url).with(body: { grant_type: 'refresh_token', refresh_token: 'refresh-1', client_id: 'commerce-client-id',
                                             client_secret: shopify_client_secret }.to_json)
  end
  let(:access_token) { ->(credentials) { credentials['access_token'] } }
  let(:orders_key) { "COMMERCE::V1::ACCOUNT::#{account.id}::STORE::#{store.id}::ORDERS::x" }

  def error_for
    yield
    nil
  rescue Commerce::Error => e
    e.as_json
  end

  it 'uses a token that is not about to expire without refreshing it' do
    store.update!(credentials: store.credentials.merge('access_token_expires_at' => 30.minutes.from_now.utc.iso8601))

    expect(described_class.new(store).with_credentials(&access_token)).to eq('access-1')
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'refreshes within five minutes of expiry and saves the new pair, with the expiry times Shopify sent, in one write' do
    stub_request(:post, token_url).to_return(status: 200, body: refreshed)

    freeze_time do
      expect(described_class.new(store).with_credentials(&access_token)).to eq('access-2')
      expect(store.reload.credentials).to eq('access_token' => 'access-2', 'refresh_token' => 'refresh-2', 'scope' => 'read_customers,read_orders',
                                             'access_token_expires_at' => 3600.seconds.from_now.utc.iso8601,
                                             'refresh_token_expires_at' => 7_776_000.seconds.from_now.utc.iso8601)
    end
    expect(refresh_request).to have_been_made.once
    expect(store.metadata).to include('token_refreshed_at')
  end

  it 'refreshes an expired token' do
    store.update!(credentials: store.credentials.merge('access_token_expires_at' => 1.minute.ago.utc.iso8601))
    stub_request(:post, token_url).to_return(status: 200, body: refreshed)

    expect(described_class.new(store).with_credentials(&access_token)).to eq('access-2')
  end

  it 'sends one refresh when ten readers need the token at the same time' do
    stub_request(:post, token_url).to_return do
      sleep 0.3
      { status: 200, body: refreshed }
    end

    store_id = store.id
    tokens = Array.new(10) { Thread.new { described_class.new(Commerce::Store.find(store_id)).with_credentials(&access_token) } }.map(&:value)

    expect(tokens).to all(eq('access-2'))
    expect(a_request(:post, token_url)).to have_been_made.once
  end

  describe 'a refresh that can be sent again (Shopify returns the same new pair for a repeated refresh)' do
    it 'resends it once right away after a timeout, with the same refresh token' do
      stub_request(:post, token_url).to_raise(Net::ReadTimeout).then.to_return(status: 200, body: refreshed)

      expect(described_class.new(store).with_credentials(&access_token)).to eq('access-2')
      expect(refresh_request).to have_been_made.twice
    end

    it 'resends it once after a network failure, a 5xx or an unreadable answer' do
      [[{ exception: Errno::ECONNRESET }], [{ status: 503, body: 'busy' }], [{ status: 200, body: '{"access_token":"half"}' }]].each do |(failure)|
        store.update!(credentials: store.credentials.merge('access_token' => 'access-1', 'refresh_token' => 'refresh-1',
                                                           'access_token_expires_at' => access_expires_at.utc.iso8601), metadata: {})
        stub = stub_request(:post, token_url)
        stub = failure[:exception] ? stub.to_raise(failure[:exception]) : stub.to_return(failure)
        stub.then.to_return(status: 200, body: refreshed)

        expect(described_class.new(store.reload).with_credentials(&access_token)).to eq('access-2')
        expect(refresh_request).to have_been_made.twice
        WebMock.reset!
      end
    end

    it 'keeps the tokens when both attempts fail, uses the unexpired token and waits a minute before trying again' do
      stub_request(:post, token_url).to_timeout.then.to_return(status: 502).then.to_return(status: 200, body: refreshed)

      expect(described_class.new(store).with_credentials(&access_token)).to eq('access-1')
      expect(described_class.new(store.reload).with_credentials(&access_token)).to eq('access-1')
      expect(a_request(:post, token_url)).to have_been_made.twice
      expect(store.reload).to have_attributes(status: 'active')
      expect(store.credentials['refresh_token']).to eq('refresh-1')

      travel 61.seconds do
        expect(described_class.new(store.reload).with_credentials(&access_token)).to eq('access-2')
      end
    end

    it 'reports an expired token whose refresh failed twice, keeping the tokens for the next attempt' do
      store.update!(credentials: store.credentials.merge('access_token_expires_at' => 1.minute.ago.utc.iso8601))
      stub_request(:post, token_url).to_raise(Net::ReadTimeout)

      expect(error_for { described_class.new(store).with_credentials(&access_token) }).to eq(code: 'TIMEOUT', reason: 'unknown_outcome')
      expect(error_for { described_class.new(store.reload).with_credentials(&access_token) })
        .to eq(code: 'STORE_UNAVAILABLE', reason: 'shopify_refresh_backoff')
      expect(a_request(:post, token_url)).to have_been_made.twice
      expect(store.reload).to have_attributes(status: 'active')
      expect(store.credentials).to include('access_token' => 'access-1', 'refresh_token' => 'refresh-1')
    end

    it 'does not resend a rate-limited refresh right away' do
      stub_request(:post, token_url).to_return(status: 429)

      expect(described_class.new(store).with_credentials(&access_token)).to eq('access-1')
      expect(a_request(:post, token_url)).to have_been_made.once
    end
  end

  describe 'a refresh token Shopify no longer accepts' do
    before { Redis::Alfred.set(orders_key, '{}') }

    it 'moves the store to needs_reauth when Shopify refuses the refresh token, removing the tokens and cached data' do
      stub_request(:post, token_url).to_return(status: 400, body: '{"error":"invalid_request"}')

      expect(error_for { described_class.new(store).with_credentials(&access_token) }).to eq(code: 'AUTH_INVALID', reason: 'refresh_token_rejected')
      expect(store.reload).to have_attributes(status: 'needs_reauth', credentials: nil)
      expect(Redis::Alfred.exists?(orders_key)).to be(false)
      expect(a_request(:post, token_url)).to have_been_made.once
    end

    it 'treats a revoked app the same way: the API and the refresh both answer 401' do
      store.update!(credentials: store.credentials.merge('access_token_expires_at' => 30.minutes.from_now.utc.iso8601))
      stub_request(:post, token_url).to_return(status: 401, body: '{"error":"invalid_token"}')

      error = error_for { described_class.new(store).with_credentials { raise Commerce::Error, 'AUTH_INVALID' } }

      expect(error).to eq(code: 'AUTH_INVALID', reason: 'refresh_token_rejected')
      expect(store.reload.status).to eq('needs_reauth')
    end

    it 'does not send a refresh token past its own expiry' do
      store.update!(credentials: store.credentials.merge('refresh_token_expires_at' => 1.minute.ago.utc.iso8601))

      expect(error_for { described_class.new(store).with_credentials(&access_token) }).to eq(code: 'AUTH_INVALID', reason: 'refresh_token_expired')
      expect(a_request(:post, token_url)).not_to have_been_made
      expect(store.reload.status).to eq('needs_reauth')
    end

    it 'keeps the tokens when Shopify rejects the app itself, since that is a configuration problem' do
      stub_request(:post, token_url).to_return(status: 401, body: '{"error":"invalid_client"}')

      expect(described_class.new(store).with_credentials(&access_token)).to eq('access-1')
      expect(store.reload).to have_attributes(status: 'active')
    end
  end

  describe 'a token Shopify rejects before its expiry (401)' do
    before { store.update!(credentials: store.credentials.merge('access_token_expires_at' => 30.minutes.from_now.utc.iso8601)) }

    it 'refreshes once and retries once' do
      stub_request(:post, token_url).to_return(status: 200, body: refreshed)
      calls = []

      result = described_class.new(store).with_credentials do |credentials|
        calls << credentials['access_token']
        raise Commerce::Error, 'AUTH_INVALID' if credentials['access_token'] == 'access-1'

        'orders'
      end

      expect(result).to eq('orders')
      expect(calls).to eq(%w[access-1 access-2])
      expect(refresh_request).to have_been_made.once
    end

    it 'uses a token another process refreshed meanwhile instead of refreshing again' do
      stale = Commerce::Store.find(store.id)
      store.update!(credentials: store.credentials.merge('access_token' => 'access-3'))

      result = described_class.new(stale).with_credentials do |credentials|
        raise Commerce::Error, 'AUTH_INVALID' if credentials['access_token'] == 'access-1'

        credentials['access_token']
      end

      expect(result).to eq('access-3')
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it 'moves the store to needs_reauth when the refreshed token is rejected too' do
      stub_request(:post, token_url).to_return(status: 200, body: refreshed)

      error = error_for { described_class.new(store).with_credentials { raise Commerce::Error, 'AUTH_INVALID' } }

      expect(error).to eq(code: 'AUTH_INVALID', reason: 'tokens_rejected')
      expect(store.reload.status).to eq('needs_reauth')
    end

    it 'never falls back to cached data while the refresh has to wait' do
      stub_request(:post, token_url).to_raise(Net::ReadTimeout)

      error = error_for { described_class.new(store).with_credentials { raise Commerce::Error, 'AUTH_INVALID' } }

      expect(error).to eq(code: 'AUTH_INVALID', reason: 'shopify_refresh_pending')
      expect(store.reload).to have_attributes(status: 'active')
    end
  end

  it 'refuses a store that needs re-authorization, without calling Shopify' do
    store.update!(status: :needs_reauth)

    expect(error_for { described_class.new(store).with_credentials(&access_token) }).to eq(code: 'AUTH_INVALID')
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'keeps tokens and the client secret out of logs, errors and the audit log' do
    stub_request(:post, token_url).to_return(status: 200, body: refreshed).then
                                  .to_return(status: 400, body: '{"error":"invalid_request","error_description":"refresh-2 is not valid"}')
    logged = []
    allow(Rails.logger).to receive(:info) { |message| logged << message }
    allow(Rails.logger).to receive(:warn) { |message| logged << message }

    described_class.new(store).with_credentials(&access_token)
    error = travel(58.minutes) { error_for { described_class.new(store.reload).with_credentials(&access_token) } }

    audit = Custom::AuditLog.where(auditable: store).order(:id)
    expect(audit.map(&:comment)).to eq(%w[commerce.shopify.token_refreshed commerce.shopify.needs_reauth])
    everything = [logged.join, error.to_json, audit.to_json].join
    %w[access-1 refresh-1 access-2 refresh-2].push(shopify_client_secret).each { |secret| expect(everything).not_to include(secret) }
  end
end
