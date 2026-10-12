# frozen_string_literal: true

# Lynomia Operations Center routes - loaded from config/routes.rb via `draw :operations`
#
# Super Admin only. Authorization is enforced at the controller, by the `authenticate_super_admin!` that
# SuperAdmin::ApplicationController applies to every action -- the route carries no guard of its own, which is
# the same arrangement as every other page on this surface.
namespace :super_admin do
  resource :operations, only: [:show] do
    collection do
      get :accounts, action: :accounts
      get :issues, action: :issues
      post :open_case, action: :open_case

      # Control Center V2 (docs/product-refinement/07-operations-control-center-v2.md).
      #
      # The queue and the signal detail are reads. The three operator decisions are POSTs, each going through
      # Operations::SignalLifecycle -- which is the only writer, takes an explicit actor, and audits. None of
      # them is a GET, so none can be triggered by a link somebody pastes into a chat.
      get :queue, action: :queue
      get :signal, action: :signal
      post :acknowledge_signal, action: :acknowledge_signal
      post :suppress_signal, action: :suppress_signal
      post :resume_signal, action: :resume_signal
    end
  end
end
