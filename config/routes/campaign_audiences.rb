# frozen_string_literal: true

# Lynomia Campaigns routes (docs/campaigns/05-preview-and-dedup.md) - loaded from config/routes.rb via `draw :campaign_audiences`
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        post 'campaigns/audience_preview', to: 'campaigns/audience_previews#create'
      end
    end
  end
end
