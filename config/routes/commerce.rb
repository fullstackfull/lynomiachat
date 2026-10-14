# frozen_string_literal: true

# Lynomia Commerce routes - loaded from config/routes.rb via `draw :commerce`
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :commerce do
          resources :stores, only: [:index, :create, :update, :destroy]
          resources :carts, only: [:index]
          resource :audience_fields, only: [:show]
          resource :salla_connection, only: [:show, :create]
          resource :zid_connection, only: [:create]
          resource :shopify_connection, only: [:create]
        end

        resources :conversations, only: [] do
          scope module: :conversations do
            namespace :commerce do
              resource :overview, only: [:show]
              resource :refresh, only: [:create]
              resources :orders, only: [:index]
              resources :action_runs, only: [:show]
              resources :carts, only: [:index]
              resources :stores, only: [:index, :show] do
                member do
                  get :customers
                  post :link
                  delete :link, action: :unlink
                end
                resources :orders, only: [] do
                  resource :actions, only: [:show, :create], controller: 'order_actions'
                end
                resources :carts, only: [], constraints: { cart_id: /[\w-]{1,64}/ } do
                  resource :recovery, only: [:create]
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

# The delivery URL of the webhooks Lynomia creates in a connected WooCommerce store
post 'webhooks/woocommerce/:store_id', to: 'webhooks/woocommerce#create', constraints: { store_id: /\d+/ }

# Store Syria commerce events. No store id in the path: Store Syria registers no webhook here
# and so never learns Lynomia's row id, so a delivery names the store by the external id it
# issues itself, in a header the signature covers.
post 'webhooks/storesyria', to: 'webhooks/storesyria#create'

# The OAuth callback URL of the Lynomia Zid app, and the target URL of each connected Zid store's webhooks
get 'commerce/zid/callback', to: 'commerce/zid/callbacks#show'
post 'webhooks/zid/:store_id', to: 'webhooks/zid#create', constraints: { store_id: /\d+/ }

# The OAuth redirect URL and the webhook URI of the Lynomia Commerce Shopify app -- Lynomia's one Shopify
# integration. The legacy integration's /shopify/callback and /webhooks/shopify were retired in
# docs/product-refinement/02-shopify-retirement.md; these paths keep their distinct names so an existing
# Shopify app registration does not have to be re-pointed.
get 'commerce/shopify/callback', to: 'commerce/shopify/callbacks#show'
post 'webhooks/shopify_commerce', to: 'webhooks/shopify_commerce#create'
