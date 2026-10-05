# frozen_string_literal: true

# Lynomia WhatsApp Template Manager routes - loaded from config/routes.rb via `draw :whatsapp_templates`.
# Reopens the api/v1/accounts/whatsapp namespace the authorization and manual-setup routes already live in.
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :whatsapp do
          resources :message_templates, only: [:index, :show]
        end
      end
    end
  end
end
