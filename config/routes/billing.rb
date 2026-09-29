# frozen_string_literal: true

# Billing routes - loaded from config/routes.rb via `draw :billing`
namespace :super_admin do
  resources :billing_plans do
    collection do
      get :settings
      patch :settings, action: :update_settings
    end
  end

  resources :billing_subscriptions, only: [:index, :show] do
    member do
      post :extend_trial
      post :grant_plan
      post :cancel_subscription
    end
  end
end

namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        resource :billing, only: [:show], controller: 'billing' do
          get :plans
          get :entitlements
          post :checkout
          post :portal
          post :change_plan_preview
          post :change_plan
        end
      end
    end
  end
end

# Billing Platform API (Platform App token)
namespace :platform, defaults: { format: 'json' } do
  namespace :api do
    namespace :v1 do
      namespace :billing do
        resources :plans, only: [:index, :show, :create, :update, :destroy] do
          get :features, on: :collection
          member do
            post :sync
            get :subscribers
          end
        end
        resource :settings, only: [:show, :update]
        resource :stats, only: [:show]
        resources :subscriptions, only: [:index, :show], param: :account_id do
          member do
            post :change_plan_preview
            post :change_plan
            post :extend_trial
            post :grant_plan
            post :cancel
            post :checkout_link
            post :portal_link
          end
        end
      end
    end
  end
end

# Stripe webhooks
post 'billing/webhooks/stripe', to: 'billing/webhooks#stripe'

# Mobile app sign-in with Google / Apple
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    namespace :mobile do
      post 'auth/google', to: 'auth#google'
      post 'auth/apple', to: 'auth#apple'
    end
  end
end

# Page Stripe sends mobile customers to; it opens the app (deep link)
get 'mobile/billing/return', to: 'mobile/billing_returns#show'