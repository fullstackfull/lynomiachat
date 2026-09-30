require 'rails_helper'

# Lynomia Commerce: the Zid app settings. The switch and the Client ID are plain values; the Client Secret is write-only
# like every config typed `secret`. No merchant token is ever stored here.
RSpec.describe 'Super Admin Zid app settings', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:client_secret) { 'zid-client-secret-0123456789' }

  around do |example|
    GlobalConfig.clear_cache
    example.run
  ensure
    GlobalConfig.clear_cache
  end

  before do
    create(:installation_config, name: 'ZID_CLIENT_SECRET', value: client_secret, locked: false)
    create(:installation_config, name: 'ZID_CLIENT_ID', value: '4821', locked: false)
    sign_in(super_admin, scope: :super_admin)
  end

  it 'declares exactly the client secret as a secret' do
    expect(InstallationConfig.secret_names).to include('ZID_CLIENT_SECRET')
    expect(InstallationConfig.secret_names).not_to include('ZID_ENABLED', 'ZID_CLIENT_ID')
  end

  it 'shows every Zid field with the secret masked and empty' do
    get '/super_admin/app_config?config=zid'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('app_config[ZID_ENABLED]', 'app_config[ZID_CLIENT_ID]', 'app_config[ZID_CLIENT_SECRET]', '4821')
    expect(response.body).not_to include(client_secret)
    expect(response.body).to include('type="password"')
  end

  it 'saves the switch and client id and keeps the stored secret when its field is left blank' do
    post '/super_admin/app_config?config=zid', params: { app_config: { ZID_ENABLED: 'true', ZID_CLIENT_ID: '4822', ZID_CLIENT_SECRET: '' } }
    GlobalConfig.clear_cache

    expect(response).to redirect_to(super_admin_settings_path)
    expect(Commerce::Zid::Config.enabled?).to be(true)
    expect(Commerce::Zid::Config.client_id).to eq('4822')
    expect(Commerce::Zid::Config.client_secret).to eq(client_secret)
  end

  it 'keeps the secret out of the generic installation configs page and out of request logs' do
    get '/super_admin/installation_configs'
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(response.body).not_to include(client_secret)
    expect(filter.filter('app_config' => { 'ZID_CLIENT_SECRET' => client_secret })).to eq('app_config' => { 'ZID_CLIENT_SECRET' => '[FILTERED]' })
  end
end
