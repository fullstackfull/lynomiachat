require 'rails_helper'

# Lynomia: WHATSAPP_APP_SECRET (and every config typed `secret`) is write-only in Super Admin.
RSpec.describe 'Super Admin WhatsApp App Secret', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:app_secret) { 'meta-app-secret-0123456789abcdef' }

  before do
    create(:installation_config, name: 'WHATSAPP_APP_SECRET', value: app_secret, locked: false)
    create(:installation_config, name: 'WHATSAPP_APP_ID', value: '1234567890', locked: false)
    sign_in(super_admin, scope: :super_admin)
  end

  it 'is declared as a secret' do
    expect(InstallationConfig.secret_names).to include('WHATSAPP_APP_SECRET')
  end

  it 'renders a masked, empty field instead of the stored secret' do
    get '/super_admin/app_config?config=whatsapp_embedded'

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include(app_secret)
    expect(response.body).to include('type="password"')
    expect(response.body).to include('1234567890')
  end

  it 'keeps the stored secret when the field is left blank' do
    post '/super_admin/app_config?config=whatsapp_embedded',
         params: { app_config: { WHATSAPP_APP_ID: '1234567890', WHATSAPP_APP_SECRET: '' } }

    expect(response).to redirect_to(super_admin_settings_path)
    expect(GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)).to eq(app_secret)
  end

  it 'replaces the secret when a new one is entered' do
    post '/super_admin/app_config?config=whatsapp_embedded',
         params: { app_config: { WHATSAPP_APP_SECRET: 'rotated-meta-app-secret' } }

    expect(response).to redirect_to(super_admin_settings_path)
    expect(GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)).to eq('rotated-meta-app-secret')
  end

  it 'is not listed in the generic installation configs page' do
    get '/super_admin/installation_configs'

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include(app_secret)
    expect(response.body).not_to include('WHATSAPP_APP_SECRET')
  end

  it 'is filtered from request logs' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(filter.filter('app_config' => { 'WHATSAPP_APP_SECRET' => app_secret })).to eq('app_config' => { 'WHATSAPP_APP_SECRET' => '[FILTERED]' })
  end
end
