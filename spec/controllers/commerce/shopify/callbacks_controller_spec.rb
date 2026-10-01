require 'rails_helper'

RSpec.describe 'Shopify Commerce OAuth callback', type: :request do
  include_context 'with commerce encryption'
  include_context 'with shopify commerce app'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:shop) { 'lynomia-demo.myshopify.com' }
  let(:settings) { "https://app.lynomia.test/app/accounts/#{account.id}/settings/commerce" }
  let(:token_url) { "https://#{shop}/admin/oauth/access_token" }
  let(:graphql_url) { "https://#{shop}/admin/api/2026-07/graphql.json" }
  let(:token_body) { JSON.parse(file_fixture('commerce/shopify/token.json').read) }
  # "Connect with Shopify" as the administrator's browser does it: the state comes back in Shopify's redirect, the cookie stays.
  let(:start) do
    lambda do
      post "/api/v1/accounts/#{account.id}/commerce/shopify_connection", params: { shop: shop }, headers: admin.create_new_auth_token, as: :json
      Rack::Utils.parse_query(URI(response.parsed_body['authorize_url']).query)['state']
    end
  end
  let(:state) { start.call }
  # Shopify's redirect: the query it signs with the app's client secret.
  let(:signed) do
    lambda do |query, secret = shopify_client_secret|
      query = { 'host' => 'YWRtaW4uc2hvcGlmeS5jb20vc3RvcmUvbHlub21pYS1kZW1v', 'shop' => shop, 'timestamp' => Time.current.to_i.to_s }.merge(query)
      query.merge('hmac' => OpenSSL::HMAC.hexdigest('SHA256', secret, URI.encode_www_form(query.sort).gsub('+', '%20')))
    end
  end

  before do
    account.enable_features!('lynomia_commerce')
    stub_request(:post, token_url).to_return(status: 200, body: token_body.to_json)
    stub_request(:post, graphql_url).to_return(status: 200, body: file_fixture('commerce/shopify/shop.json').read)
  end

  it 'exchanges the code server-side for an expiring offline token, confirms the shop and connects it to the account in the state' do
    freeze_time do
      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => state)

      expect(response).to redirect_to("#{settings}?shopify=connected")
      store = account.commerce_stores.sole
      expect(store).to have_attributes(provider: 'shopify', external_store_id: '68210001', name: 'Lynomia Demo',
                                       base_url: 'https://lynomia-demo.myshopify.com', status: 'active', created_by: admin)
      expect(store.credentials).to eq('access_token' => 'shpat_fixture_access_token_0001', 'refresh_token' => 'shprt_fixture_refresh_token_0001',
                                      'access_token_expires_at' => 3600.seconds.from_now.utc.iso8601,
                                      'refresh_token_expires_at' => 7_776_000.seconds.from_now.utc.iso8601, 'scope' => 'read_customers,read_orders')
      expect(a_request(:post, token_url).with(body: { code: 'shopify-code-1', expiring: '1', client_id: 'commerce-client-id',
                                                      client_secret: shopify_client_secret }.to_json)).to have_been_made.once
      expect(a_request(:post, graphql_url).with(headers: { 'X-Shopify-Access-Token' => 'shpat_fixture_access_token_0001' })).to have_been_made.once
    end
  end

  it 'stores the tokens only encrypted and never hands them, or the client secret, to the browser or the logs' do
    io = StringIO.new
    loggers = [Rails.logger, ActionController::Base.logger]
    Rails.logger = ActionController::Base.logger = ActiveSupport::Logger.new(io)
    issued = state
    begin
      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => issued)
    ensure
      Rails.logger, ActionController::Base.logger = loggers
    end

    raw = Commerce::Store.connection.select_value("SELECT credentials FROM commerce_stores WHERE provider = 'shopify'")
    secrets = ['shpat_fixture_access_token_0001', 'shprt_fixture_refresh_token_0001', shopify_client_secret, 'shopify-code-1', issued]
    secrets.each do |secret|
      expect(raw).not_to include(secret)
      expect(io.string).not_to include(secret)
      expect(response.location).not_to include(secret)
    end
    expect(io.string).to include('/commerce/shopify/callback')
    audit = defined?(Enterprise::AuditLog) ? Enterprise::AuditLog.where(auditable: account.commerce_stores.sole).pluck(:audited_changes) : []
    expect(audit.to_json).not_to include('shpat_', 'shprt_')
  end

  describe 'the callback signature, checked before the state and the code' do
    it 'refuses a missing, wrong or wrong-key signature without consuming the state' do
      issued = state
      unsigned = { 'code' => 'shopify-code-1', 'state' => issued, 'shop' => shop, 'timestamp' => Time.current.to_i.to_s }
      [
        unsigned,
        unsigned.merge('hmac' => 'f' * 64),
        signed.call({ 'code' => 'shopify-code-1', 'state' => issued }, 'legacy-shopify-app-secret')
      ].each do |query|
        get '/commerce/shopify/callback', params: query

        expect(response).to redirect_to('https://app.lynomia.test/app')
      end
      expect(a_request(:post, token_url)).not_to have_been_made

      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => issued)
      expect(response).to redirect_to("#{settings}?shopify=connected")
    end

    it 'refuses a query modified after Shopify signed it' do
      query = signed.call('code' => 'shopify-code-1', 'state' => state)

      [query.merge('code' => 'other-code'), query.merge('account_id' => '1'), query.merge('shop' => 'attacker.myshopify.com')].each do |modified|
        get '/commerce/shopify/callback', params: modified

        expect(response).to redirect_to('https://app.lynomia.test/app')
      end
      expect(a_request(:post, token_url)).not_to have_been_made
      expect(a_request(:post, 'https://attacker.myshopify.com/admin/oauth/access_token')).not_to have_been_made
    end

    it 'refuses a signed callback older than 90 seconds' do
      query = signed.call('code' => 'shopify-code-1', 'state' => state)

      travel 2.minutes do
        get '/commerce/shopify/callback', params: query
      end

      expect(response).to redirect_to('https://app.lynomia.test/app')
      expect(a_request(:post, token_url)).not_to have_been_made
    end
  end

  describe 'the state' do
    it 'refuses a forged state' do
      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => 'forged')

      expect(response).to redirect_to('https://app.lynomia.test/app')
      expect(a_request(:post, token_url)).not_to have_been_made
      expect(Commerce::Store.count).to eq(0)
    end

    it 'accepts a state once: a replayed callback changes nothing' do
      issued = state
      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => issued)
      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-2', 'state' => issued)

      expect(response).to redirect_to('https://app.lynomia.test/app')
      expect(a_request(:post, token_url)).to have_been_made.once
    end

    it 'refuses an expired state' do
      issued = state
      travel 11.minutes do
        get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => issued)
      end

      expect(response).to redirect_to('https://app.lynomia.test/app')
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it "refuses another browser's callback, such as a state leaked to an agent" do
      issued = state
      cookies.delete('lynomia_shopify_oauth')

      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => issued)

      expect(response).to redirect_to('https://app.lynomia.test/app')
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it 'refuses a validly signed callback for a shop other than the one the administrator started with' do
      issued = state
      stub_request(:post, 'https://other-shop.myshopify.com/admin/oauth/access_token')

      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => issued, 'shop' => 'other-shop.myshopify.com')

      expect(response).to redirect_to('https://app.lynomia.test/app')
      expect(a_request(:post, 'https://other-shop.myshopify.com/admin/oauth/access_token')).not_to have_been_made
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it 'refuses a Zid state' do
      zid = Commerce::OauthState.issue('zid', account: account, user: admin)
      cookies['lynomia_shopify_oauth'] = zid.nonce

      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => zid.state)

      expect(response).to redirect_to('https://app.lynomia.test/app')
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it 'takes the account only from the state, never from query parameters' do
      other = create(:account)
      other.enable_features!('lynomia_commerce')

      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => state, 'account_id' => other.id.to_s)

      expect(response).to redirect_to("#{settings}?shopify=connected")
      expect(other.commerce_stores).to be_empty
    end
  end

  describe 'the administrator and the switches, checked again at the callback' do
    it 'refuses a user who is no longer an administrator' do
      issued = state
      admin.account_users.find_by!(account: account).update!(role: :agent)

      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => issued)

      expect(response).to redirect_to("#{settings}?shopify_error=PERMISSION_DENIED")
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it 'refuses when the account lost Commerce in the meantime' do
      issued = state
      account.disable_features!('lynomia_commerce')

      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => issued)

      expect(response).to redirect_to("#{settings}?shopify_error=PERMISSION_DENIED")
      expect(a_request(:post, token_url)).not_to have_been_made
    end

    it 'refuses when the installation switched Shopify Commerce off in the meantime' do
      issued = state
      InstallationConfig.find_by!(name: 'SHOPIFY_COMMERCE_ENABLED').update!(value: false)
      GlobalConfig.clear_cache

      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => issued)

      expect(response).to redirect_to("#{settings}?shopify_error=PROVIDER_DISABLED")
      expect(a_request(:post, token_url)).not_to have_been_made
    end
  end

  describe 'the token and the shop' do
    it 'saves nothing without a code or when Shopify rejects it' do
      get '/commerce/shopify/callback', params: signed.call('state' => start.call)
      expect(response).to redirect_to("#{settings}?shopify_error=AUTH_INVALID")

      stub_request(:post, token_url).to_return(status: 400, body: '{"error":"invalid_request"}')
      get '/commerce/shopify/callback', params: signed.call('code' => 'used-code', 'state' => start.call)
      expect(response).to redirect_to("#{settings}?shopify_error=AUTH_INVALID")
      expect(Commerce::Store.count).to eq(0)
    end

    it 'refuses a token that is not an expiring offline token' do
      stub_request(:post, token_url).to_return(status: 200, body: { access_token: 'shpat_x', scope: 'read_customers,read_orders' }.to_json)

      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => state)

      expect(response).to redirect_to("#{settings}?shopify_error=INVALID_RESPONSE")
      expect(Commerce::Store.count).to eq(0)
      expect(a_request(:post, graphql_url)).not_to have_been_made
    end

    it 'refuses a token without the read scopes or with anything beyond read access' do
      ['read_orders', 'read_customers,read_orders,write_orders'].each do |scope|
        stub_request(:post, token_url).to_return(status: 200, body: token_body.merge('scope' => scope).to_json)

        get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => start.call)

        expect(response).to redirect_to("#{settings}?shopify_error=PERMISSION_DENIED")
      end
      expect(Commerce::Store.count).to eq(0)
    end

    it 'asks for write_orders only when an administrator reconnects for order actions the installation offers' do
      post "/api/v1/accounts/#{account.id}/commerce/shopify_connection", params: { shop: shop, order_actions: true },
                                                                         headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('error' => { 'code' => 'ACTIONS_DISABLED', 'reason' => 'provider_actions_disabled' })

      InstallationConfig.where(name: 'SHOPIFY_COMMERCE_ACTIONS_ENABLED').first_or_initialize.update!(value: true, locked: false)
      GlobalConfig.clear_cache
      with_modified_env(COMMERCE_ALLOW_PRE_UAT_PROVIDERS: 'true') do
        post "/api/v1/accounts/#{account.id}/commerce/shopify_connection", params: { shop: shop, order_actions: true },
                                                                           headers: admin.create_new_auth_token, as: :json
      end
      expect(Rack::Utils.parse_query(URI(response.parsed_body['authorize_url']).query)['scope']).to eq('read_customers,read_orders,write_orders')

      start.call
      expect(Rack::Utils.parse_query(URI(response.parsed_body['authorize_url']).query)['scope']).to eq('read_customers,read_orders')
    end

    it 're-authorizes for order actions only with write_orders granted, and keeps the read-only store working otherwise' do
      store = create(:commerce_store, :shopify, account: account, external_store_id: '68210001', base_url: "https://#{shop}")
      issued = Commerce::OauthState.issue('shopify', account: account, user: admin, shop: shop, scopes: 'read_customers,read_orders,write_orders')
      cookie = issued.nonce
      allow(Commerce::OauthState).to(receive(:consume).and_wrap_original { |original, *args| original.call(args[0], args[1], cookie) })

      stub_request(:post, token_url).to_return(status: 200, body: token_body.to_json)
      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => issued.state)
      expect(response).to redirect_to("#{settings}?shopify_error=PERMISSION_DENIED")
      expect(store.reload.credentials['scope']).to eq('read_customers,read_orders')

      issued = Commerce::OauthState.issue('shopify', account: account, user: admin, shop: shop, scopes: 'read_customers,read_orders,write_orders')
      cookie = issued.nonce
      stub_request(:post, token_url).to_return(status: 200, body: token_body.merge('scope' => 'read_customers,write_orders').to_json)
      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-2', 'state' => issued.state)
      expect(response).to redirect_to("#{settings}?shopify=connected")
      expect(store.reload.credentials['scope']).to eq('read_customers,write_orders')
      expect(Commerce::Providers.for(store).write_access_problem).to be_nil
    end

    it 'refuses a token whose shop is not the shop in the state, and a shop another account owns' do
      other_shop = { data: { shop: { id: 'gid://shopify/Shop/9', name: 'X', myshopifyDomain: 'x.myshopify.com' } } }
      stub_request(:post, graphql_url).to_return(status: 200, body: other_shop.to_json)
      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => state)
      expect(response).to redirect_to("#{settings}?shopify_error=AUTH_INVALID")

      create(:commerce_store, :shopify, account: create(:account), external_store_id: '68210001', base_url: "https://#{shop}")
      stub_request(:post, graphql_url).to_return(status: 200, body: file_fixture('commerce/shopify/shop.json').read)
      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => start.call)
      expect(response).to redirect_to("#{settings}?shopify_error=STORE_ALREADY_CONNECTED")
      expect(account.commerce_stores).to be_empty
    end

    it "re-authorizes the account's own store in place, keeping a disabled store disabled" do
      needs_reauth = create(:commerce_store, :shopify, account: account, external_store_id: '68210001', base_url: "https://#{shop}",
                                                       status: :needs_reauth, credentials: nil)

      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => state)

      expect(response).to redirect_to("#{settings}?shopify=connected")
      expect(needs_reauth.reload).to have_attributes(status: 'active')
      expect(needs_reauth.credentials['access_token']).to eq('shpat_fixture_access_token_0001')

      needs_reauth.update!(status: :disabled)
      get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => start.call)
      expect(needs_reauth.reload.status).to eq('disabled')
      expect(account.commerce_stores.count).to eq(1)
    end
  end

  it 'leaves the legacy Shopify callback and its hooks untouched' do
    hook = create(:integrations_hook, account: create(:account), app_id: 'shopify', reference_id: shop, access_token: 'legacy-token')

    get '/commerce/shopify/callback', params: signed.call('code' => 'shopify-code-1', 'state' => state)

    expect(response).to redirect_to("#{settings}?shopify=connected")
    expect(hook.reload).to have_attributes(access_token: 'legacy-token', status: 'enabled', reference_id: shop)
    expect(Rails.application.routes.recognize_path('/shopify/callback')).to eq(controller: 'shopify/callbacks', action: 'show')
  end
end
