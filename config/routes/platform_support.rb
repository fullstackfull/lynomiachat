# frozen_string_literal: true

# Platform Support Desk routes - loaded from config/routes.rb via `draw :platform_support`
# (docs/platform-support/12-refresh-against-product-refinement.md §2).
#
# TWO SURFACES IN ONE DRAWER, and only one of them is an API.
#
# The tenant side is JSON under /api/v1/accounts/:account_id/platform_support/, authenticated by the existing
# dashboard session or an api_access_token and authorized by Pundit, so a mobile client inherits all of it and
# needs no new auth story. `namespace :platform_support` nests the MODULE as well as the path, which is what is
# wanted: the controller is Api::V1::Accounts::PlatformSupport::TicketsController.
#
# The staff side is server-rendered ERB inside the existing Super Admin shell, following the Operations V2
# precedent: `authenticate_super_admin!` from SuperAdmin::ApplicationController, plus the one extra layer
# Operations does not have -- a before_action resolving an active PlatformSupport::Agent. It is deliberately
# NOT a JSON API in V1, because that would mean designing a second cross-account authentication story the
# console does not have.
#
# EVERY STAFF MUTATION IS POST OR PATCH, never GET, so none can be triggered by a link somebody pastes into a
# chat. Reads are GET.
#
# ONE STAFF CONTROLLER, ON PURPOSE. Administrate enumerates every controller under super_admin/ from this route
# table and raises for one with no index route and no dashboard, so each distinct controller name here needs a
# matching entry in the exclusion array in app/views/super_admin/application/_navigation.html.erb -- and
# omitting one breaks the sidebar on EVERY Super Admin page. Keeping the whole desk on
# SuperAdmin::PlatformSupportController means that array needs exactly one new entry: "platform_support".
#
# There is NO tenant route for internal notes -- not a filtered one, not a 403 one, none -- and no `destroy`
# anywhere: a ticket is closed, never deleted.
namespace :api, defaults: { format: 'json' } do
  namespace :v1 do
    resources :accounts, only: [] do
      scope module: :accounts do
        namespace :platform_support do
          resources :tickets, only: [:index, :show, :create, :update] do
            resources :messages, only: [:index, :create]
            resources :events, only: [:index]
            member do
              post :mark_viewed
            end
          end
          # The first authorized ActiveStorage download in this repository: it authorizes the blob's PARENT
          # record through the policy scope and then streams, so an internal note's attachment 404s as a
          # consequence of that lookup. No serializer anywhere emits a blob URL.
          resources :attachments, only: [:show]
        end
      end
    end
  end
end

namespace :super_admin do
  # The operator desk. TWO controllers, not one: `platform_support` holds the reads and
  # `platform_support_actions` (which inherits from it, and so inherits the acting-agent guard) holds the six
  # decisions, so a read path can never be reached by a verb that writes. Both names are in the Administrate
  # exclusion array at app/views/super_admin/application/_navigation.html.erb -- Administrate enumerates every
  # controller under super_admin/ from this route table and raises for one with no index route and no
  # dashboard, so a controller added here without that entry breaks EVERY Super Admin page.
  #
  # Reads are GET and every mutation is POST or PATCH, following config/routes/operations.rb.
  #
  # `agents` and `sla_policies` are deliberately absent: the first PlatformSupport::Agent row cannot be created
  # from a page that is itself behind the acting-agent guard, so it is created by
  # `rails platform_support:grant_agent` instead (lib/tasks/platform_support.rake), and SLA policy records wait
  # on the owner's target values (docs/platform-support/12 §11).
  # `controller:` is required: without it a singular `resource :platform_support` routes to
  # PlatformSupportsController and the queue 404s.
  resource :platform_support, only: [:show], controller: 'platform_support' do
    collection do
      get 'tickets/:id', action: :ticket, as: :ticket
      get 'attachments/:id', action: :attachment, as: :attachment

      post 'tickets/:id/reply', action: :reply, as: :reply, controller: 'platform_support_actions'
      post 'tickets/:id/note', action: :note, as: :note, controller: 'platform_support_actions'
      patch 'tickets/:id/status', action: :status, as: :status, controller: 'platform_support_actions'
      patch 'tickets/:id/triage', action: :triage, as: :triage, controller: 'platform_support_actions'
      post 'tickets/:id/assign', action: :assign, as: :assign, controller: 'platform_support_actions'
    end
  end
end
