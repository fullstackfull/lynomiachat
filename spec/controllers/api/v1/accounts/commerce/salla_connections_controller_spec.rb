require 'rails_helper'

RSpec.describe 'Salla connection API', type: :request do
  include_context 'with commerce encryption'
  include_context 'with salla app'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/commerce/salla_connection" }

  before { account.enable_features!('lynomia_commerce') }

  it 'gives an administrator a one-time code and the Salla install link, then reports progress' do
    post path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('install_url' => 'https://s.salla.sa/apps/install/1234567890', 'code' => /\A[A-Z2-9-]{19}\z/)

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('status' => 'waiting')
    expect(response.body).not_to include('digest')
  end

  it 'is refused to agents' do
    post path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'is unavailable when lynomia_commerce is off' do
    account.disable_features!('lynomia_commerce')

    post path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'is refused while the installation has Salla switched off' do
    InstallationConfig.find_by!(name: 'SALLA_ENABLED').update!(value: false)
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
