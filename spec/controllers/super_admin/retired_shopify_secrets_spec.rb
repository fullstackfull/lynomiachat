require 'rails_helper'

# Retiring the legacy Shopify integration took its three `type: secret` declarations out of
# config/installation_config.yml with it. ConfigLoader never deletes a row, so on an installation that once
# configured it the values stay in the database -- and classification read from the YAML alone would no longer
# know they are secrets, which is how the generic Installation Configs page came to list them
# (docs/product-refinement/MERGE_GATE.md §V1). InstallationConfig::RETIRED_SECRET_NAMES is where that knowledge
# now lives, and these examples are the guard on it.
RSpec.describe 'Retired Shopify installation configs', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:client_id) { 'shopify-client-id-0123456789' }
  let(:client_secret) { 'shpss-client-secret-0123456789' }
  let(:partner_token) { 'shppa-partner-access-token-0123456789' }

  around do |example|
    GlobalConfig.clear_cache
    example.run
  ensure
    GlobalConfig.clear_cache
  end

  before do
    # Exactly the rows the retired Super Admin form left behind: editable, with a stored value.
    create(:installation_config, name: 'SHOPIFY_CLIENT_ID', value: client_id, locked: false)
    create(:installation_config, name: 'SHOPIFY_CLIENT_SECRET', value: client_secret, locked: false)
    create(:installation_config, name: 'SHOPIFY_PARTNER_ACCESS_TOKEN', value: partner_token, locked: false)
    sign_in(super_admin, scope: :super_admin)
  end

  # The property the fix exists for: nothing declares these keys any more, and they are still secrets.
  it 'classifies all three retired keys as secrets although nothing declares them' do
    declared = ConfigLoader.new.general_configs.map { |config| config['name'] }

    expect(declared).not_to include('SHOPIFY_CLIENT_ID')
    expect(declared).not_to include('SHOPIFY_CLIENT_SECRET')
    expect(declared).not_to include('SHOPIFY_PARTNER_ACCESS_TOKEN')
    expect(InstallationConfig.secret_names).to include('SHOPIFY_CLIENT_ID')
    expect(InstallationConfig.secret_names).to include('SHOPIFY_CLIENT_SECRET')
    expect(InstallationConfig.secret_names).to include('SHOPIFY_PARTNER_ACCESS_TOKEN')
  end

  it 'keeps a stale row out of the generic Installation Configs listing, name and value alike' do
    get '/super_admin/installation_configs'

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include(client_secret)
    expect(response.body).not_to include(partner_token)
    expect(response.body).not_to include(client_id)
    expect(response.body).not_to include('SHOPIFY_CLIENT_SECRET')
    expect(response.body).not_to include('SHOPIFY_PARTNER_ACCESS_TOKEN')
    expect(response.body).not_to include('SHOPIFY_CLIENT_ID')
  end

  # Administrate resolves show, edit and update through the same scope as the listing
  # (Administrate::ApplicationController#find_resource), so an excluded row cannot be reached by guessing its id.
  #
  # One request per example deliberately: in the test environment the first unhandled RecordNotFound renders
  # Rails' debug page, and a second request in the same example comes back as a redirect rather than a 404 --
  # an artefact of that page, not of the controller.
  it 'serves no retired secret from its own page either' do
    row = InstallationConfig.find_by(name: 'SHOPIFY_CLIENT_SECRET')

    get "/super_admin/installation_configs/#{row.id}"

    expect(response).to have_http_status(:not_found)
  end

  it 'is the secret classification that excludes it, not the id' do
    listed = InstallationConfig.editable.where.not(name: InstallationConfig.secret_names).pluck(:name)

    expect(listed).not_to include('SHOPIFY_CLIENT_ID')
    expect(listed).not_to include('SHOPIFY_CLIENT_SECRET')
    expect(listed).not_to include('SHOPIFY_PARTNER_ACCESS_TOKEN')
  end

  # They must not come back as settings an operator can fill in: the legacy Shopify page is gone, and the id it
  # used now falls through to the general form, which does not carry these fields.
  it 'offers no Super Admin form that writes a retired key' do
    get '/super_admin/app_config?config=shopify'

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include('app_config[SHOPIFY_CLIENT_ID]')
    expect(response.body).not_to include('app_config[SHOPIFY_CLIENT_SECRET]')
    expect(response.body).not_to include('app_config[SHOPIFY_PARTNER_ACCESS_TOKEN]')
    expect(response.body).not_to include(client_secret)
  end

  it 'ignores a retired key posted to the app config form rather than storing it' do
    post '/super_admin/app_config?config=general',
         params: { app_config: { SHOPIFY_CLIENT_SECRET: 'a-newly-posted-secret', SHOPIFY_CLIENT_ID: 'a-newly-posted-id' } }

    expect(InstallationConfig.find_by(name: 'SHOPIFY_CLIENT_SECRET').value).to eq(client_secret)
    expect(InstallationConfig.find_by(name: 'SHOPIFY_CLIENT_ID').value).to eq(client_id)
  end

  # The retirement itself, re-asserted here because a stale credential only matters if the path that used it
  # could come back. The generic hook writer's refusal and the empty app catalogue are asserted in
  # spec/controllers/api/v1/accounts/integrations/hooks_controller_spec.rb and spec/models/integrations/app_spec.rb;
  # these are the account-API ingresses no other spec names.
  it 'leaves every legacy Shopify ingress unrouted' do
    expect { Rails.application.routes.recognize_path('/api/v1/accounts/1/integrations/shopify/auth', method: :post) }
      .to raise_error(ActionController::RoutingError)
    expect { Rails.application.routes.recognize_path('/api/v1/accounts/1/integrations/shopify/orders', method: :get) }
      .to raise_error(ActionController::RoutingError)
    expect { Rails.application.routes.recognize_path('/api/v1/accounts/1/integrations/shopify', method: :delete) }
      .to raise_error(ActionController::RoutingError)
  end
end
