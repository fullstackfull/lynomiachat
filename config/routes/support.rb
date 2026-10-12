# frozen_string_literal: true

# Lynomia Support routes - loaded from config/routes.rb via `draw :support`
#
# `namespace :support` nests the module as well as the path, which is what is wanted here: the path is
# /api/v1/accounts/:account_id/support/tickets and the controller is
# Api::V1::Accounts::Support::TicketsController.
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :support do
          resources :tickets, only: [:index, :show, :create, :update] do
            resources :events, only: [:index, :create]
          end
          resources :sla_policies, only: [:index, :show, :create, :update, :destroy]
        end
      end
    end
  end
end
