# frozen_string_literal: true

# Lynomia Commerce routes - loaded from config/routes.rb via `draw :commerce`
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :commerce do
          resources :stores, only: [:index, :create, :update, :destroy]
        end
      end
    end
  end
end
