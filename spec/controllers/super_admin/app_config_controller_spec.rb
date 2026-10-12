require 'rails_helper'

RSpec.describe 'Super Admin Application Config API', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        get '/super_admin/app_config'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      let!(:config) { create(:installation_config, { name: 'FB_APP_ID', value: 'TESTVALUE' }) }

      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        get '/super_admin/app_config?config=facebook'
        expect(response).to have_http_status(:success)
        expect(response.body).to include(config.value)
      end
    end
  end

  describe 'POST /super_admin/app_config' do
    context 'when it is an unauthenticated super admin' do
      it 'returns unauthorized' do
        post '/super_admin/app_config', params: { app_config: { TESTKEY: 'TESTVALUE' } }
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an aunthenticated super admin' do
      it 'shows the app_config page' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=facebook', params: { app_config: { FB_APP_ID: 'FB_APP_ID' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:notice]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:success]).to be_blank

        config = GlobalConfig.get('FB_APP_ID')
        expect(config['FB_APP_ID']).to eq('FB_APP_ID')
      end

      it 'asks admins to restart web and worker processes for runtime config changes' do
        sign_in(super_admin, scope: :super_admin)
        post '/super_admin/app_config?config=captain', params: { app_config: { CAPTAIN_OPEN_AI_ENDPOINT: 'https://api.openai.com' } }

        expect(response).to have_http_status(:found)
        expect(response).to redirect_to(super_admin_settings_path)
        expect(flash[:success]).to be_present
        expect(flash[:alert]).to be_blank
        expect(flash[:notice]).to be_blank
      end

      # The two Shopify Partner API validation examples that lived here went with the legacy Shopify
      # integration (docs/product-refinement/02-shopify-retirement.md §2.3). The credentials they validated are
      # no longer product configuration and no runtime code ever read them. What replaces them is the property
      # that matters now: this form owns a closed set of keys per config page, so a legacy key submitted into
      # it is dropped rather than written.
      it 'drops a submitted key that the requested config page does not own' do
        sign_in(super_admin, scope: :super_admin)

        post '/super_admin/app_config?config=shopify_commerce',
             params: { app_config: { SHOPIFY_COMMERCE_CLIENT_ID: 'commerce-id', SHOPIFY_CLIENT_ID: 'hijacked' } }

        expect(response).to redirect_to(super_admin_settings_path)
        expect(GlobalConfig.get('SHOPIFY_COMMERCE_CLIENT_ID')['SHOPIFY_COMMERCE_CLIENT_ID']).to eq('commerce-id')
        expect(GlobalConfig.get('SHOPIFY_CLIENT_ID')['SHOPIFY_CLIENT_ID']).to be_nil
      end
    end
  end
end
