# frozen_string_literal: true

# Odoo Accounting integration routes - loaded from config/routes.rb via `draw :odoo`
#
# SUPER ADMIN ONLY, and there is NO public route here at all. The brief forbids a publicly reachable Odoo
# credentials endpoint and forbids introducing a new public payment endpoint; this file introduces neither.
# Authorization is enforced at the controller by the `authenticate_super_admin!` that
# SuperAdmin::ApplicationController applies to every action -- the same arrangement as every other page on this
# surface, and the route carries no guard of its own.
#
# EVERY WRITE IS A POST OR A PATCH. Test Connection and the capability probe are POSTs even though they feel
# like reads, because the first authenticates against a third-party server and the second creates a document
# in it; neither is something a link somebody pastes into a chat should be able to do.
namespace :super_admin do
  resource :odoo_accounting, only: [:show], controller: 'odoo_accounting' do
    collection do
      # Reads: one per tab.
      get :settings
      get :customers
      get :invoices
      get :transactions
      get :history
      get :errors
      get :diagnostics
      # The import PREVIEW is a read and writes nothing; starting one is the POST below.
      get :import

      # Writes.
      patch :settings, action: :update_settings
      post :clear_api_key
      post :test_connection
      post :run_capability_probe
      post :enable
      post :disable
      post :start_import
      post :retry_event
    end
  end
end
