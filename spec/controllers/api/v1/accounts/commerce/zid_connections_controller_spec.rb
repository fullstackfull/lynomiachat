require 'rails_helper'

RSpec.describe 'Zid connection API', type: :request do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/commerce/zid_connection" }

  before { account.enable_features!('lynomia_commerce') }

  it 'gives an administrator the Zid authorization link with a signed state, and binds it to this browser' do
    post path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    url = URI(response.parsed_body['authorize_url'])
    query = Rack::Utils.parse_query(url.query)
    expect("#{url.scheme}://#{url.host}#{url.path}").to eq('https://oauth.zid.sa/oauth/authorize')
    expect(query).to include('client_id' => '4821', 'redirect_uri' => 'https://app.lynomia.test/commerce/zid/callback', 'response_type' => 'code')
    expect(query['state']).to be_present
    cookie = response.headers['set-cookie'].to_s
    expect(cookie).to include('lynomia_zid_oauth=', 'path=/commerce/zid/callback', 'httponly', 'samesite=lax')
    expect(response.body).not_to include(zid_client_secret)
  end

  it 'is refused to agents, so an agent can never start an authorization' do
    post path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['set-cookie'].to_s).not_to include('lynomia_zid_oauth')
  end

  it 'is unavailable when lynomia_commerce is off' do
    account.disable_features!('lynomia_commerce')

    post path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'is refused while the installation has Zid switched off' do
    InstallationConfig.find_by!(name: 'ZID_ENABLED').update!(value: false)
    GlobalConfig.clear_cache

    post path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('code' => 'PROVIDER_DISABLED')
  end

  it 'refuses to start without encryption, since the tokens could not be stored' do
    with_modified_env(ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY: nil) do
      post path, headers: admin.create_new_auth_token, as: :json
    end

    expect(response.parsed_body['error']).to eq('code' => 'ENCRYPTION_NOT_CONFIGURED')
  end
end
