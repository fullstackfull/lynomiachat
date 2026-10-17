# frozen_string_literal: true

# Partner integration administration (P6C) - loaded from config/routes.rb via
# `draw :partner_integrations`.
#
# Super Admin only, through the `authenticate_super_admin!` that SuperAdmin::ApplicationController
# applies to every action; the route carries no guard of its own, which is the arrangement every
# other page on this surface uses.
#
# `controller:` is named explicitly. A singular `resource :partner_integrations` would otherwise
# route to PartnerIntegrationsSController -- the same 404 config/routes/platform_support.rb
# records having hit.
#
# EVERY ACTION IS A GET because this screen has no operator mutation: changing an integration
# belongs to the Administrate screen for the app, the Operations Center for a signal, and the
# partner's own console for its installations.
namespace :super_admin do
  resource :partner_integrations, only: [:show], controller: 'partner_integrations' do
    collection do
      get :app, action: :app
    end
  end
end
