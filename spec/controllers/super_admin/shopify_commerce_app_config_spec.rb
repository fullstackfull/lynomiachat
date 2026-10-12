require 'rails_helper'

# Lynomia Commerce: the Shopify Commerce app settings -- now Lynomia's ONLY Shopify settings page, the legacy
# Shopify integration having been retired (docs/product-refinement/02-shopify-retirement.md). The Client Secret is
# write-only like every config typed `secret`. No merchant token is ever stored here.
#
# The legacy-coexistence assertions this file used to carry were replaced rather than deleted: what used to be
# "saving one never changes the other" is now "this form cannot write a key it does not own", which is the
# property that still matters once the other page is gone.
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
    # Not product configuration any more -- the legacy keys are gone from config/installation_config.yml. Rows
    # like these can still exist in a database that predates the retirement, and this form must not write them.
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

  it 'saves the switch and client id, keeps the stored secret when left blank, and ignores a key it does not own' do
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

  # There is no longer a legacy Shopify settings page to validate Partner API credentials for. The page is gone
  # from app/helpers/super_admin/features.yml, so it is not offered in the settings menu, and 'shopify' is gone
  # from the controller's config mapping, so the form never renders a legacy field.
  it 'no longer offers a second Shopify settings page' do
    get '/super_admin/settings'

    expect(response.body).not_to include('app_config?config=shopify"')
    expect(response.body).to include('app_config?config=shopify_commerce')
  end

  it 'offers no legacy Shopify field even when that config key is requested directly' do
    get '/super_admin/app_config?config=shopify'

    expect(response.body).not_to include('app_config[SHOPIFY_CLIENT_ID]', 'app_config[SHOPIFY_CLIENT_SECRET]',
                                         'app_config[ENABLE_SHOPIFY_INTEGRATION]', legacy_secret)
  end

  it 'keeps the secret out of the generic installation configs page and out of request logs' do
    get '/super_admin/installation_configs'
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(response.body).not_to include(client_secret)
    expect(filter.filter('app_config' => { 'SHOPIFY_COMMERCE_CLIENT_SECRET' => client_secret }))
      .to eq('app_config' => { 'SHOPIFY_COMMERCE_CLIENT_SECRET' => '[FILTERED]' })
  end
end
