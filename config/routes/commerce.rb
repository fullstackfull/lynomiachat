# frozen_string_literal: true

# Lynomia Commerce routes - loaded from config/routes.rb via `draw :commerce`
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :commerce do
          resources :stores, only: [:index, :create, :update, :destroy]
          resource :salla_connection, only: [:show, :create]
          resource :zid_connection, only: [:create]
          resource :shopify_connection, only: [:create]
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

# The OAuth callback URL of the Lynomia Zid app, and the target URL of each connected Zid store's webhooks
get 'commerce/zid/callback', to: 'commerce/zid/callbacks#show'
post 'webhooks/zid/:store_id', to: 'webhooks/zid#create', constraints: { store_id: /\d+/ }

# The OAuth redirect URL of the Lynomia Commerce Shopify app (not the legacy integration's /shopify/callback)
get 'commerce/shopify/callback', to: 'commerce/shopify/callbacks#show'
