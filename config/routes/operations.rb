# frozen_string_literal: true

# Lynomia Operations Center routes - loaded from config/routes.rb via `draw :operations`
#
# Super Admin only. Authorization is enforced at the controller, by the `authenticate_super_admin!` that
# SuperAdmin::ApplicationController applies to every action -- the route carries no guard of its own, which is
# the same arrangement as every other page on this surface.
namespace :super_admin do
  resource :operations, only: [:show] do
    collection do
      get :accounts, action: :accounts
      get :issues, action: :issues
      post :open_case, action: :open_case
    end
  end
end
