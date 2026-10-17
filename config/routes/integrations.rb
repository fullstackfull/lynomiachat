# frozen_string_literal: true

# External-platform account linking - loaded from config/routes.rb via `draw :integrations`.
#
# TWO SURFACES, FACING OPPOSITE WAYS, AND THAT IS THE WHOLE DESIGN.
#
# The in-account surface is where the PROOF IS MINTED. An administrator signed in to this account asks for a
# one-time code. It is authenticated by the ordinary dashboard session or an api_access_token and authorized by
# the account's own administrator role, so the only person who can produce a code for an account is somebody who
# can already sign in to it as an administrator.
#
# The platform surface is where the proof is SPENT. An external platform app presents the code over its own
# server-to-server credential and receives the account and user it was minted by. It names no account and no
# email: the only thing it can send is a string it was given, so there is nothing to point at a workspace the
# merchant cannot already reach.
#
# `account_links#create` is deliberately NOT behind validate_platform_app_permissible, and it is the one route
# in the platform namespace where that is a design decision rather than an inherited default: an app cannot
# hold a permissible on an account it has not linked yet, so requiring one would make linking impossible. The
# code IS the authorization. `destroy` is the opposite -- it acts on an account the app already holds, so it
# inherits PlatformController's permissible check through set_resource and must not opt out of it.
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :integrations do
          resource :account_link_code, only: [:show, :create]
          # The merchant's own view of what this workspace has given away, and the way to take it back.
          # Until this existed a grant could only be revoked by the app holding it, which is the least
          # likely party to volunteer.
          resources :grants, only: [:index, :destroy]
        end
      end
    end
  end
end

namespace :platform, defaults: { format: 'json' } do
  namespace :api do
    namespace :v1 do
      # POST   /platform/api/v1/account_links          redeem a code, receive the account + user it proves
      # DELETE /platform/api/v1/account_links/:id      hand every grant on that account back (:id is the account)
      resources :account_links, only: [:create, :destroy]
    end
  end
end
