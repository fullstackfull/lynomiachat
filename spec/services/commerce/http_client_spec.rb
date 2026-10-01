require 'rails_helper'

RSpec.describe Commerce::HttpClient do
  let(:base_uri) { URI('https://shop.example.com') }
  let(:client) do
    described_class.new(base_uri: base_uri, authorization: "Basic #{Base64.strict_encode64('ck_key:cs_secret')}", log_tag: 'woocommerce')
  end
  let(:url) { 'https://shop.example.com/wp-json/wc/v3/orders?per_page=1' }

  def resolve(host, *ips)
    allow(Resolv).to receive(:getaddresses).with(host).and_return(ips)
  end

  def error_for
    yield
    nil
  rescue Commerce::Error => e
    e.as_json
  end

  before { resolve('shop.example.com', '93.184.216.34') }

  it 'sends a read-only GET with HTTP Basic credentials and returns parsed JSON' do
    stub = stub_request(:get, url).with(basic_auth: %w[ck_key cs_secret], headers: { 'Accept' => 'application/json' })
                                  .to_return(status: 200, body: '[{"id":1}]')

    expect(client.get_json('/wp-json/wc/v3/orders', per_page: 1)).to eq([{ 'id' => 1 }])
    expect(stub).to have_been_requested.once
  end

  describe 'SSRF protection' do
    {
      'loopback' => '127.0.0.1', 'RFC1918 10/8' => '10.0.0.5', 'RFC1918 172.16/12' => '172.16.4.2',
      'RFC1918 192.168/16' => '192.168.1.10', 'link-local / AWS+GCP metadata' => '169.254.169.254',
      'shared address space / Alibaba metadata' => '100.100.100.200', 'unspecified' => '0.0.0.0',
      'IPv6 loopback' => '::1', 'IPv6 unique local / AWS IPv6 metadata' => 'fd00:ec2::254', 'IPv6 link-local' => 'fe80::1',
      'IPv4-mapped loopback' => '::ffff:127.0.0.1'
    }.each do |label, ip|
      it "refuses a store host resolving to #{label} (#{ip}) without connecting" do
        resolve('shop.example.com', ip)

        expect(error_for { client.get_json('/wp-json/wc/v3/orders') }).to eq(code: 'INVALID_STORE_URL', reason: 'private_address')
        expect(a_request(:any, /.*/)).not_to have_been_made
      end
    end

    it 'refuses an unresolvable host' do
      resolve('shop.example.com')

      expect(error_for { client.get_json('/wp-json/wc/v3/orders') }).to eq(code: 'STORE_UNAVAILABLE', reason: 'dns')
    end

    it 'never follows a redirect, so a store cannot bounce the request to a private address' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'http://169.254.169.254/latest/meta-data/' })

      expect(error_for { client.get_json('/wp-json/wc/v3/orders', per_page: 1) }).to eq(code: 'INVALID_STORE_URL', reason: 'redirect')
      expect(a_request(:get, /169\.254\.169\.254/)).not_to have_been_made
    end

    it 'does not follow a same-host redirect either' do
      stub_request(:get, url).to_return(status: 301, headers: { 'Location' => 'https://shop.example.com/other' })

      expect(error_for { client.get_json('/wp-json/wc/v3/orders', per_page: 1) }).to eq(code: 'INVALID_STORE_URL', reason: 'redirect')
      expect(a_request(:get, 'https://shop.example.com/other')).not_to have_been_made
    end

    it 'lets an explicitly trusted internal host through the address check (development stores)' do
      trusted = described_class.new(base_uri: URI('http://woo.internal:8081'), log_tag: 'woocommerce')
      stub_request(:get, 'http://woo.internal:8081/wp-json/wc/v3').to_return(status: 200, body: '{"namespace":"wc/v3"}')

      with_modified_env(COMMERCE_TRUSTED_STORE_HOSTS: 'woo.internal') do
        expect(trusted.get_json('/wp-json/wc/v3')).to eq('namespace' => 'wc/v3')
      end
    end

    it 'keeps untrusted internal hosts blocked when a trusted list exists' do
      resolve('shop.example.com', '10.1.2.3')

      with_modified_env(COMMERCE_TRUSTED_STORE_HOSTS: 'woo.internal') do
        expect(error_for { client.get_json('/wp-json/wc/v3') }).to eq(code: 'INVALID_STORE_URL', reason: 'private_address')
      end
    end
  end

  describe 'errors' do
    { 401 => 'AUTH_INVALID', 403 => 'PERMISSION_DENIED', 404 => 'NOT_FOUND', 429 => 'RATE_LIMITED' }.each do |status, code|
      it "maps HTTP #{status} to #{code} without the provider message" do
        stub_request(:get, url).to_return(status: status, body: '{"code":"woocommerce_rest_x","message":"Consumer secret is invalid."}')

        expect(error_for { client.get_json('/wp-json/wc/v3/orders', per_page: 1) }).to eq(code: code)
      end
    end

    it 'maps a non-JSON body to INVALID_RESPONSE' do
      stub_request(:get, url).to_return(status: 200, body: '<html>Just a moment...</html>')

      expect(error_for { client.get_json('/wp-json/wc/v3/orders', per_page: 1) }).to eq(code: 'INVALID_RESPONSE', reason: 'not_json')
    end

    it 'refuses an oversized body' do
      stub_request(:get, url).to_return(status: 200, body: 'x' * (described_class::MAX_BODY_BYTES + 1))

      expect(error_for { client.get_json('/wp-json/wc/v3/orders', per_page: 1) }).to eq(code: 'INVALID_RESPONSE', reason: 'too_large')
    end

    it 'maps TLS failures to STORE_UNAVAILABLE' do
      stub_request(:get, url).to_raise(OpenSSL::SSL::SSLError)

      expect(error_for { client.get_json('/wp-json/wc/v3/orders', per_page: 1) }).to eq(code: 'STORE_UNAVAILABLE', reason: 'tls')
    end
  end

  describe 'timeouts and retries' do
    it 'does not retry a timeout' do
      stub = stub_request(:get, url).to_timeout

      expect(error_for { client.get_json('/wp-json/wc/v3/orders', per_page: 1) }).to eq(code: 'TIMEOUT')
      expect(stub).to have_been_requested.once
    end

    it 'retries a 503 once and succeeds' do
      stub = stub_request(:get, url).to_return({ status: 503 }, { status: 200, body: '[]' })

      expect(client.get_json('/wp-json/wc/v3/orders', per_page: 1)).to eq([])
      expect(stub).to have_been_requested.twice
    end

    it 'gives up after one retry' do
      stub = stub_request(:get, url).to_return(status: 502)

      expect(error_for { client.get_json('/wp-json/wc/v3/orders', per_page: 1) }).to eq(code: 'STORE_UNAVAILABLE', reason: 'http_502')
      expect(stub).to have_been_requested.twice
    end

    it 'retries a reset connection once' do
      stub = stub_request(:get, url).to_raise(Errno::ECONNRESET).then.to_return(status: 200, body: '[]')

      expect(client.get_json('/wp-json/wc/v3/orders', per_page: 1)).to eq([])
      expect(stub).to have_been_requested.twice
    end

    it 'does not retry a 500' do
      stub = stub_request(:get, url).to_return(status: 500)

      expect(error_for { client.get_json('/wp-json/wc/v3/orders', per_page: 1) }).to eq(code: 'STORE_UNAVAILABLE', reason: 'http_500')
      expect(stub).to have_been_requested.once
    end
  end

  it 'records the rate-limit headers of the last response, rate-limited ones included' do
    stub_request(:get, url).to_return(status: 429, headers: { 'X-RateLimit-Limit' => '120', 'X-RateLimit-Remaining' => '0',
                                                              'X-RateLimit-Reset' => '1790000000', 'Retry-After' => '30' })

    expect(error_for { client.get_json('/wp-json/wc/v3/orders', per_page: 1) }).to eq(code: 'RATE_LIMITED')
    expect(client.rate_limit).to eq(limit: 120, remaining: 0, reset: 1_790_000_000, retry_after: 30)
  end

  describe '#post_form' do
    let(:token_client) { described_class.new(base_uri: URI('https://accounts.example.com'), log_tag: 'salla') }
    let(:token_url) { 'https://accounts.example.com/oauth2/token' }
    let(:form) { { grant_type: 'refresh_token', refresh_token: 'refresh-1' } }

    before { resolve('accounts.example.com', '93.184.216.35') }

    it 'sends one urlencoded POST without an Authorization header and returns the status and body, errors included' do
      stub = stub_request(:post, token_url)
             .with(body: { 'grant_type' => 'refresh_token', 'refresh_token' => 'refresh-1' },
                   headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
             .to_return(status: 400, body: '{"error":"invalid_grant"}')

      expect(token_client.post_form('/oauth2/token', form)).to eq([400, { 'error' => 'invalid_grant' }])
      expect(stub).to have_been_requested.once
      expect(a_request(:post, token_url).with { |request| request.headers.key?('Authorization') }).not_to have_been_made
    end

    it 'never retries, not even a 503 or a reset connection' do
      stub = stub_request(:post, token_url).to_return(status: 503, body: 'busy')

      expect(token_client.post_form('/oauth2/token', form)).to eq([503, nil])
      expect(stub).to have_been_requested.once
    end

    it 'reports a failure after the request may have been sent as an unknown outcome' do
      [Errno::ECONNRESET, Net::ReadTimeout, Net::WriteTimeout, EOFError].each do |failure|
        stub = stub_request(:post, token_url).to_raise(failure)

        expect(error_for { token_client.post_form('/oauth2/token', form) }).to eq(code: 'TIMEOUT', reason: 'unknown_outcome')
        expect(stub).to have_been_requested.once
        WebMock.reset!
        resolve('accounts.example.com', '93.184.216.35')
      end
    end

    it 'reports a request that never left as not sent' do
      stub_request(:post, token_url).to_timeout
      expect(error_for { token_client.post_form('/oauth2/token', form) }).to eq(code: 'STORE_UNAVAILABLE', reason: 'not_sent')

      stub_request(:post, token_url).to_raise(Errno::ECONNREFUSED)
      expect(error_for { token_client.post_form('/oauth2/token', form) }).to eq(code: 'STORE_UNAVAILABLE', reason: 'not_sent')

      resolve('accounts.example.com', '10.0.0.8')
      expect(error_for { token_client.post_form('/oauth2/token', form) }).to eq(code: 'STORE_UNAVAILABLE', reason: 'not_sent')
    end

    it 'logs the method and path only, never the form' do
      stub_request(:post, token_url).to_return(status: 200, body: '{"access_token":"new-access"}')
      logged = []
      allow(Rails.logger).to receive(:info) { |message| logged << message }

      token_client.post_form('/oauth2/token', form)

      expect(logged.join).to include('metric=commerce.provider.request client=salla method=POST path=/oauth2/token status=200')
      expect(logged.join).not_to include('refresh-1', 'new-access')
    end
  end

  describe '#post_json_status' do
    let(:token_client) { described_class.new(base_uri: URI('https://lynomia-demo.myshopify.com'), log_tag: 'shopify') }
    let(:token_url) { 'https://lynomia-demo.myshopify.com/admin/oauth/access_token' }

    before { resolve('lynomia-demo.myshopify.com', '93.184.216.60') }

    it 'sends one JSON POST and returns the status and body, errors included, without retrying' do
      stub = stub_request(:post, token_url).with(body: { 'grant_type' => 'refresh_token', 'refresh_token' => 'refresh-1' },
                                                 headers: { 'Content-Type' => 'application/json' })
                                           .to_return(status: 502, body: '{"error":"bad gateway"}')

      expect(token_client.post_json_status('/admin/oauth/access_token', grant_type: 'refresh_token', refresh_token: 'refresh-1'))
        .to eq([502, { 'error' => 'bad gateway' }])
      expect(stub).to have_been_requested.once
    end

    it 'classifies transport failures like #post_form' do
      stub_request(:post, token_url).to_raise(Net::ReadTimeout)
      expect(error_for { token_client.post_json_status('/admin/oauth/access_token', {}) }).to eq(code: 'TIMEOUT', reason: 'unknown_outcome')

      stub_request(:post, token_url).to_raise(Errno::ECONNREFUSED)
      expect(error_for { token_client.post_json_status('/admin/oauth/access_token', {}) }).to eq(code: 'STORE_UNAVAILABLE', reason: 'not_sent')
    end
  end

  it 'sends a Bearer token as given' do
    bearer = described_class.new(base_uri: URI('https://shop.example.com/admin/v2'), authorization: 'Bearer access-1', log_tag: 'salla')
    stub = stub_request(:get, 'https://shop.example.com/admin/v2/orders').with(headers: { 'Authorization' => 'Bearer access-1' })
                                                                         .to_return(status: 200, body: '{"data":[]}')

    expect(bearer.get_json('/orders')).to eq('data' => [])
    expect(stub).to have_been_requested.once
  end

  describe 'Zid requests' do
    let(:zid) do
      described_class.new(base_uri: URI('https://api.zid.sa/v1'), authorization: 'Bearer auth-1', headers: { 'X-Manager-Token' => 'manager-1' },
                          log_tag: 'zid')
    end
    let(:webhooks) { 'https://api.zid.sa/v1/managers/webhooks' }

    before { resolve('api.zid.sa', '93.184.216.51') }

    it 'sends both of the store tokens with every request' do
      stub = stub_request(:get, "#{webhooks}?page=1").with(headers: { 'Authorization' => 'Bearer auth-1', 'X-Manager-Token' => 'manager-1' })
                                                     .to_return(status: 200, body: '{"data":[]}')

      expect(zid.get_json('/managers/webhooks', page: 1)).to eq('data' => [])
      expect(stub).to have_been_requested.once
    end

    it 'posts JSON once, never retrying' do
      stub = stub_request(:post, webhooks).with(body: { event: 'order.create' }.to_json, headers: { 'Content-Type' => 'application/json' })
                                          .to_return(status: 503)

      expect(error_for { zid.post_json('/managers/webhooks', event: 'order.create') }).to eq(code: 'STORE_UNAVAILABLE', reason: 'http_503')
      expect(stub).to have_been_requested.once
    end

    it 'deletes once and reports errors by code' do
      stub = stub_request(:delete, "#{webhooks}?original_id=4821").to_return(status: 404)

      expect(error_for { zid.delete('/managers/webhooks', original_id: '4821') }).to eq(code: 'NOT_FOUND')
      stub_request(:delete, "#{webhooks}?original_id=4821").to_return(status: 204)
      expect(zid.delete('/managers/webhooks', original_id: '4821')).to eq(204)
      expect(stub).to have_been_requested.twice
    end
  end

  it 'logs the path and status only: no credentials, no query (it can carry an email or phone)' do
    stub_request(:get, 'https://shop.example.com/wp-json/wc/v3/orders?search=omar@example.com').to_return(status: 200, body: '[]')
    logged = []
    allow(Rails.logger).to receive(:info) { |message| logged << message }

    client.get_json('/wp-json/wc/v3/orders', search: 'omar@example.com')

    expect(logged.join).to include('metric=commerce.provider.request client=woocommerce method=GET path=/wp-json/wc/v3/orders status=200')
    expect(logged.join).not_to include('omar', 'ck_key', 'cs_secret')
  end
end
