require 'rails_helper'

RSpec.describe 'Shopify Commerce connection API', type: :request do
  include_context 'with commerce encryption'
  include_context 'with shopify commerce app'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/commerce/shopify_connection" }

  before { account.enable_features!('lynomia_commerce') }

  it "gives an administrator the shop's authorization link with a signed state bound to the shop and this browser" do
    post path, params: { shop: ' Lynomia-Demo.myshopify.com ' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    url = URI(response.parsed_body['authorize_url'])
    query = Rack::Utils.parse_query(url.query)
    expect("#{url.scheme}://#{url.host}#{url.path}").to eq('https://lynomia-demo.myshopify.com/admin/oauth/authorize')
    expect(query).to include('client_id' => 'commerce-client-id', 'scope' => 'read_customers,read_orders',
                             'redirect_uri' => 'https://app.lynomia.test/commerce/shopify/callback')
    expect(query.keys).not_to include('grant_options[]')
    expect(query['state']).to be_present
    expect(response.headers['set-cookie'].to_s).to include('lynomia_shopify_oauth=', 'path=/commerce/shopify/callback', 'httponly', 'samesite=lax')
    expect(response.body).not_to include(shopify_client_secret)
  end

  it 'accepts only a myshopify.com shop domain' do
    [
      'evil.com', 'lynomia-demo.myshopify.com.evil.com', 'evil.com/lynomia-demo.myshopify.com', 'https://lynomia-demo.myshopify.com',
      'lynomia-demo.myshopify.com:443', 'user@lynomia-demo.myshopify.com', 'lynomia-demo.myshopify.com/admin', 'lynomia-demo.myshopify.com?x=1',
      'lynomia-demo.myshopify.com#x', "lynomia-demo.myshopify.com\n.evil.com", '127.0.0.1', '169.254.169.254', '-demo.myshopify.com',
      'demo..myshopify.com', 'myshopify.com', 'lynomia-demo.shopify.com', 'xn--lynomia-mnchen.myshopify.com.', '', nil, ['lynomia-demo.myshopify.com']
    ].each do |shop|
      post path, params: { shop: shop }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity), shop.inspect
      expect(response.parsed_body['error']).to eq('code' => 'INVALID_STORE_URL', 'reason' => 'shopify_domain')
      expect(response.headers['set-cookie'].to_s).not_to include('lynomia_shopify_oauth')
    end
  end

  it 'refuses a shop this account already shows through the legacy Shopify integration, leaving that integration alone' do
    hook = create(:integrations_hook, account: account, app_id: 'shopify', reference_id: 'lynomia-demo.myshopify.com', access_token: 'legacy-token')

    post path, params: { shop: 'lynomia-demo.myshopify.com' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('code' => 'STORE_ALREADY_CONNECTED', 'reason' => 'legacy_shopify_integration')
    expect(hook.reload).to have_attributes(access_token: 'legacy-token', status: 'enabled')
  end

  it "is not blocked by another account's legacy integration or by another legacy shop" do
    create(:integrations_hook, account: create(:account), app_id: 'shopify', reference_id: 'lynomia-demo.myshopify.com')
    create(:integrations_hook, account: account, app_id: 'shopify', reference_id: 'other-shop.myshopify.com')

    post path, params: { shop: 'lynomia-demo.myshopify.com' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
  end

  it 'is refused to agents, so an agent can never start an authorization' do
    post path, params: { shop: 'lynomia-demo.myshopify.com' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['set-cookie'].to_s).not_to include('lynomia_shopify_oauth')
  end

  it 'is unavailable when lynomia_commerce is off' do
    account.disable_features!('lynomia_commerce')

    post path, params: { shop: 'lynomia-demo.myshopify.com' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'is refused while the installation has Shopify Commerce switched off, whatever the legacy integration setting' do
    InstallationConfig.find_by!(name: 'SHOPIFY_COMMERCE_ENABLED').update!(value: false)
    InstallationConfig.where(name: 'ENABLE_SHOPIFY_INTEGRATION').first_or_initialize.update!(value: true, locked: false)
    GlobalConfig.clear_cache

    post path, params: { shop: 'lynomia-demo.myshopify.com' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('code' => 'PROVIDER_DISABLED')
  end

  it 'refuses to start without encryption, since the tokens could not be stored' do
    with_modified_env(ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY: nil) do
      post path, params: { shop: 'lynomia-demo.myshopify.com' }, headers: admin.create_new_auth_token, as: :json
    end

    expect(response.parsed_body['error']).to eq('code' => 'ENCRYPTION_NOT_CONFIGURED')
  end
end
