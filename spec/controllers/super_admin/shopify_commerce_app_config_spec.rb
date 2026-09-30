require 'rails_helper'

# Lynomia Commerce: the Shopify Commerce app settings. They are separate from the legacy Shopify integration settings:
# saving one never changes the other, and the legacy Partner API validation does not run for them. The Client Secret is
# write-only like every config typed `secret`. No merchant token is ever stored here.
RSpec.describe 'Super Admin Shopify Commerce app settings', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:client_secret) { 'shpss_commerce_secret_0123456789' }
  let(:legacy_secret) { 'shpss_legacy_secret_0123456789' }

  around do |example|
    GlobalConfig.clear_cache
    example.run
  ensure
    GlobalConfig.clear_cache
  end

  before do
    create(:installation_config, name: 'SHOPIFY_COMMERCE_CLIENT_SECRET', value: client_secret, locked: false)
    create(:installation_config, name: 'SHOPIFY_COMMERCE_CLIENT_ID', value: 'commerce-client-id', locked: false)
    create(:installation_config, name: 'SHOPIFY_CLIENT_ID', value: 'legacy-client-id', locked: false)
    create(:installation_config, name: 'SHOPIFY_CLIENT_SECRET', value: legacy_secret, locked: false)
    sign_in(super_admin, scope: :super_admin)
  end

  it 'declares exactly the client secret as a secret' do
    expect(InstallationConfig.secret_names).to include('SHOPIFY_COMMERCE_CLIENT_SECRET')
    expect(InstallationConfig.secret_names).not_to include('SHOPIFY_COMMERCE_ENABLED', 'SHOPIFY_COMMERCE_CLIENT_ID')
  end

  it 'shows only the Shopify Commerce fields with the secret masked and empty' do
    get '/super_admin/app_config?config=shopify_commerce'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('app_config[SHOPIFY_COMMERCE_ENABLED]', 'app_config[SHOPIFY_COMMERCE_CLIENT_ID]',
                                     'app_config[SHOPIFY_COMMERCE_CLIENT_SECRET]', 'commerce-client-id', 'type="password"')
    expect(response.body).not_to include(client_secret, legacy_secret, 'app_config[SHOPIFY_CLIENT_ID]', 'legacy-client-id')
  end

  it 'saves the switch and client id, keeps the stored secret when left blank and leaves the legacy settings alone' do
    post '/super_admin/app_config?config=shopify_commerce',
         params: { app_config: { SHOPIFY_COMMERCE_ENABLED: 'true', SHOPIFY_COMMERCE_CLIENT_ID: 'commerce-client-id-2',
                                 SHOPIFY_COMMERCE_CLIENT_SECRET: '', SHOPIFY_CLIENT_ID: 'hijacked' } }
    GlobalConfig.clear_cache

    expect(response).to redirect_to(super_admin_settings_path)
    expect(Commerce::Shopify::Config.enabled?).to be(true)
    expect(Commerce::Shopify::Config.client_id).to eq('commerce-client-id-2')
    expect(Commerce::Shopify::Config.client_secret).to eq(client_secret)
    expect(InstallationConfig.find_by(name: 'SHOPIFY_CLIENT_ID').value).to eq('legacy-client-id')
    expect(InstallationConfig.find_by(name: 'SHOPIFY_CLIENT_SECRET').value).to eq(legacy_secret)
    expect(InstallationConfig.find_by(name: 'ENABLE_SHOPIFY_INTEGRATION')&.value).not_to be(true)
  end

  it 'does not run the legacy Partner API validation' do
    expect(Shopify::PartnerConfiguration).not_to receive(:validate_for_save!)

    post '/super_admin/app_config?config=shopify_commerce', params: { app_config: { SHOPIFY_COMMERCE_CLIENT_ID: 'commerce-client-id-3' } }

    expect(response).to redirect_to(super_admin_settings_path)
  end

  it 'keeps the secret out of the generic installation configs page and out of request logs' do
    get '/super_admin/installation_configs'
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(response.body).not_to include(client_secret)
    expect(filter.filter('app_config' => { 'SHOPIFY_COMMERCE_CLIENT_SECRET' => client_secret }))
      .to eq('app_config' => { 'SHOPIFY_COMMERCE_CLIENT_SECRET' => '[FILTERED]' })
  end
end
