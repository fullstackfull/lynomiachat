require 'rails_helper'

# Lynomia Commerce: the Salla app settings. The App ID and Client ID are plain values; the Client Secret and the
# Webhook Secret are write-only like every config typed `secret`.
RSpec.describe 'Super Admin Salla app settings', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:client_secret) { 'salla-client-secret-0123456789' }
  let(:webhook_secret) { 'salla-webhook-secret-0123456789' }

  around do |example|
    GlobalConfig.clear_cache
    example.run
  ensure
    GlobalConfig.clear_cache
  end

  before do
    create(:installation_config, name: 'SALLA_CLIENT_SECRET', value: client_secret, locked: false)
    create(:installation_config, name: 'SALLA_WEBHOOK_SECRET', value: webhook_secret, locked: false)
    create(:installation_config, name: 'SALLA_CLIENT_ID', value: 'salla-client-id-42', locked: false)
    sign_in(super_admin, scope: :super_admin)
  end

  it 'declares exactly the client and webhook secrets as secrets' do
    expect(InstallationConfig.secret_names).to include('SALLA_CLIENT_SECRET', 'SALLA_WEBHOOK_SECRET')
    expect(InstallationConfig.secret_names).not_to include('SALLA_ENABLED', 'SALLA_APP_ID', 'SALLA_CLIENT_ID')
  end

  it 'shows every Salla field with the secrets masked and empty' do
    get '/super_admin/app_config?config=salla'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('app_config[SALLA_ENABLED]', 'app_config[SALLA_APP_ID]', 'app_config[SALLA_CLIENT_ID]',
                                     'app_config[SALLA_CLIENT_SECRET]', 'app_config[SALLA_WEBHOOK_SECRET]', 'salla-client-id-42')
    expect(response.body).not_to include(client_secret, webhook_secret)
    expect(response.body).to include('type="password"')
  end

  it 'saves the switch and ids and keeps the stored secrets when their fields are left blank' do
    post '/super_admin/app_config?config=salla',
         params: { app_config: { SALLA_ENABLED: 'true', SALLA_APP_ID: '1234567890', SALLA_CLIENT_ID: 'salla-client-id-42',
                                 SALLA_CLIENT_SECRET: '', SALLA_WEBHOOK_SECRET: '' } }
    GlobalConfig.clear_cache

    expect(response).to redirect_to(super_admin_settings_path)
    expect(Commerce::Salla::Config.enabled?).to be(true)
    expect(Commerce::Salla::Config.install_url).to eq('https://s.salla.sa/apps/install/1234567890')
    expect(Commerce::Salla::Config.client_secret).to eq(client_secret)
    expect(Commerce::Salla::Config.webhook_secret).to eq(webhook_secret)
  end

  it 'keeps the secrets out of the generic installation configs page and out of request logs' do
    get '/super_admin/installation_configs'
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(response.body).not_to include(client_secret, webhook_secret)
    expect(filter.filter('app_config' => { 'SALLA_CLIENT_SECRET' => client_secret, 'SALLA_WEBHOOK_SECRET' => webhook_secret }))
      .to eq('app_config' => { 'SALLA_CLIENT_SECRET' => '[FILTERED]', 'SALLA_WEBHOOK_SECRET' => '[FILTERED]' })
  end
end
