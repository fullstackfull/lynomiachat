# frozen_string_literal: true

# Lynomia Analytics routes - loaded from config/routes.rb via `draw :analytics`
#
# Written as explicit `to:` mappings rather than a namespace, matching the existing campaign analytics routes in
# config/routes.rb. A `namespace :analytics` here would nest the module as well as the path and resolve to
# api/v1/accounts/analytics/accounts, which is not the controller.
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        # The canonical analytics contract for this account: timezone, resolved range, families and filters.
        get 'analytics', to: 'analytics#meta'
        # The metric endpoints land here as their screens arrive (P8.2 onwards), on the same controller:
        #   get 'analytics/overview', to: 'analytics#overview'
      end
    end
  end
end
