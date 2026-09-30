# frozen_string_literal: true

# Lynomia Commerce routes - loaded from config/routes.rb via `draw :commerce`
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :commerce do
          resources :stores, only: [:index, :create, :update, :destroy]
          resource :salla_connection, only: [:show, :create]
        end

        resources :conversations, only: [] do
          scope module: :conversations do
            namespace :commerce do
              resources :stores, only: [:index, :show] do
                member do
                  get :customers
                  post :link
                  delete :link, action: :unlink
                end
              end
            end
          end
        end
      end
    end
  end
end

# Salla app events (the webhook URL of the Lynomia Salla app)
post 'webhooks/salla', to: 'webhooks/salla#create'
