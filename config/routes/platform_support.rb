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
  get 'platform_support', to: 'platform_support#index', as: :platform_support

  scope path: 'platform_support', controller: :platform_support, as: :platform_support do
    get 'tickets/:id', action: :show, as: :ticket
    post 'tickets/:id/reply', action: :reply, as: :ticket_reply
    post 'tickets/:id/note', action: :note, as: :ticket_note
    patch 'tickets/:id/status', action: :status, as: :ticket_status
    patch 'tickets/:id/triage', action: :triage, as: :ticket_triage
    post 'tickets/:id/assign', action: :assign, as: :ticket_assign
    get 'attachments/:id', action: :attachment, as: :attachment

    # Operator administration of the staff rows and the SLA policy records. Both are reads plus writes on the
    # same controller for the reason above; editing a policy additionally requires a `lead`.
    get 'agents', action: :agents, as: :agents
    post 'agents', action: :create_agent, as: :create_agent
    patch 'agents/:id', action: :update_agent, as: :update_agent
    get 'sla_policies', action: :sla_policies, as: :sla_policies
    post 'sla_policies', action: :create_sla_policy, as: :create_sla_policy
    patch 'sla_policies/:id', action: :update_sla_policy, as: :update_sla_policy
  end
end
