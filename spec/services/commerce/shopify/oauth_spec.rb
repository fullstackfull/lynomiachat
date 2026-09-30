require 'rails_helper'

RSpec.describe Commerce::Shopify::Oauth do
  include_context 'with shopify commerce app'

  let(:shop) { 'lynomia-demo.myshopify.com' }
  let(:now) { Time.zone.at(1_790_000_000) }
  let(:query) do
    { 'code' => 'code-1', 'host' => 'YWRtaW4uc2hvcGlmeS5jb20vc3RvcmUvbHlub21pYS1kZW1v', 'shop' => shop, 'state' => 'state+1/2=',
      'timestamp' => '1790000000' }
  end
  # The message Shopify signs for `query`, written out by hand: sorted, form-encoded, '+' '/' '=' escaped.
  let(:message) do
    'code=code-1&host=YWRtaW4uc2hvcGlmeS5jb20vc3RvcmUvbHlub21pYS1kZW1v&shop=lynomia-demo.myshopify.com&state=state%2B1%2F2%3D&timestamp=1790000000'
  end
  let(:hmac) { OpenSSL::HMAC.hexdigest('SHA256', shopify_client_secret, message) }

  describe '.authorize_url' do
    it "sends the browser to the shop's own authorize page for an offline token with the read-only scopes" do
      url = URI(described_class.authorize_url(shop, 'state-1'))
      params = Rack::Utils.parse_query(url.query)

      expect("#{url.scheme}://#{url.host}#{url.path}").to eq('https://lynomia-demo.myshopify.com/admin/oauth/authorize')
      expect(params).to eq('client_id' => 'commerce-client-id', 'scope' => 'read_customers,read_orders',
                           'redirect_uri' => 'https://app.lynomia.test/commerce/shopify/callback', 'state' => 'state-1')
    end
  end

  describe '.valid_callback?' do
    it "accepts Shopify's signature over the canonical query, including a space written as %20" do
      spaced = query.merge('locale' => 'en US')
      spaced_hmac = OpenSSL::HMAC.hexdigest('SHA256', shopify_client_secret, message.sub('&shop=', '&locale=en%20US&shop='))

      expect(described_class.valid_callback?(query.merge('hmac' => hmac), now: now)).to be(true)
      expect(described_class.valid_callback?(spaced.merge('hmac' => spaced_hmac), now: now)).to be(true)
    end

    it 'ignores a legacy `signature` parameter, like the official libraries' do
      expect(described_class.valid_callback?(query.merge('hmac' => hmac, 'signature' => 'anything'), now: now)).to be(true)
    end

    it 'refuses a missing, wrong or wrong-key signature' do
      wrong_key = OpenSSL::HMAC.hexdigest('SHA256', 'legacy-app-secret', message)

      expect(described_class.valid_callback?(query, now: now)).to be(false)
      expect(described_class.valid_callback?(query.merge('hmac' => ''), now: now)).to be(false)
      expect(described_class.valid_callback?(query.merge('hmac' => hmac.reverse), now: now)).to be(false)
      expect(described_class.valid_callback?(query.merge('hmac' => wrong_key), now: now)).to be(false)
    end

    it 'refuses a query changed after signing: a value, an added or a removed parameter' do
      expect(described_class.valid_callback?(query.merge('hmac' => hmac, 'shop' => 'attacker.myshopify.com'), now: now)).to be(false)
      expect(described_class.valid_callback?(query.merge('hmac' => hmac, 'account_id' => '7'), now: now)).to be(false)
      expect(described_class.valid_callback?(query.except('host').merge('hmac' => hmac), now: now)).to be(false)
    end

    it 'refuses a signature older or newer than 90 seconds, or without a timestamp' do
      expect(described_class.valid_callback?(query.merge('hmac' => hmac), now: now + 90)).to be(true)
      expect(described_class.valid_callback?(query.merge('hmac' => hmac), now: now + 91)).to be(false)
      expect(described_class.valid_callback?(query.merge('hmac' => hmac), now: now - 91)).to be(false)

      unsigned_time = query.except('timestamp')
      signature = OpenSSL::HMAC.hexdigest('SHA256', shopify_client_secret, message.sub('&timestamp=1790000000', ''))
      expect(described_class.valid_callback?(unsigned_time.merge('hmac' => signature), now: now)).to be(false)
    end

    it 'refuses repeated or nested parameters' do
      expect(described_class.valid_callback?(query.merge('hmac' => hmac, 'shop' => [shop]), now: now)).to be(false)
      expect(described_class.valid_callback?(query.merge('hmac' => hmac, 'x' => { 'y' => '1' }), now: now)).to be(false)
      expect(described_class.valid_callback?(query.merge('hmac' => [hmac]), now: now)).to be(false)
    end
  end

  describe '.token' do
    it "posts one JSON request to the shop's token endpoint with the client credentials" do
      stub = stub_request(:post, 'https://lynomia-demo.myshopify.com/admin/oauth/access_token')
             .with(body: { code: 'code-1', expiring: '1', client_id: 'commerce-client-id', client_secret: shopify_client_secret }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
             .to_return(status: 200, body: '{"access_token":"a"}')

      expect(described_class.token(shop, code: 'code-1', expiring: '1')).to eq([200, { 'access_token' => 'a' }])
      expect(stub).to have_been_requested.once
    end
  end

  describe '.identity' do
    let(:graphql_url) { 'https://lynomia-demo.myshopify.com/admin/api/2026-07/graphql.json' }

    it "is the shop's numeric id and name, confirmed with the access token" do
      stub = stub_request(:post, graphql_url).with(headers: { 'X-Shopify-Access-Token' => 'access-1' })
                                             .to_return(status: 200, body: file_fixture('commerce/shopify/shop.json').read)

      expect(described_class.identity(shop, 'access-1')).to eq(external_store_id: '68210001', name: 'Lynomia Demo')
      expect(stub).to have_been_requested.once
    end

    it 'refuses a token that belongs to another shop, or an unexpected shop id' do
      other = { data: { shop: { id: 'gid://shopify/Shop/5', name: 'Other', myshopifyDomain: 'other.myshopify.com' } } }.to_json
      stub_request(:post, graphql_url).to_return(status: 200, body: other)
      expect { described_class.identity(shop, 'access-1') }.to raise_error(Commerce::Error, 'AUTH_INVALID: shopify_shop_mismatch')

      odd = { data: { shop: { id: 'gid://shopify/Customer/5', name: 'Demo', myshopifyDomain: shop } } }.to_json
      stub_request(:post, graphql_url).to_return(status: 200, body: odd)
      expect { described_class.identity(shop, 'access-1') }.to raise_error(Commerce::Error, 'INVALID_RESPONSE: shopify_shop')
    end
  end
end
