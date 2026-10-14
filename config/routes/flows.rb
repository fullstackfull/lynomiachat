# frozen_string_literal: true

# Lynomia Flow Builder routes - loaded from config/routes.rb via `draw :flows`
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        resources :flows, only: [:index, :create, :show, :update, :destroy] do
          # Which of the account's channels can run an automation, and which one each is running.
          get :channels, on: :collection
          member do
            put :draft
            post :duplicate
            post :publish
            post :disable
            get :sessions
            post :simulate
          end
        end
      end
    end
  end
end
