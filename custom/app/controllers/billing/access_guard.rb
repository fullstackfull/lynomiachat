# frozen_string_literal: true

# Included into Api::V1::Accounts::BaseController by config/initializers/billing.rb
#
# 1. Blocks every account-scoped API request (/api/v1/accounts/:id/...) when the
#    account has no usable subscription. The billing API itself stays open.
# 2. Rejects adding agents when the plan's agent limit is reached, before
#    Chatwoot starts creating the user.
module Billing::AccessGuard
  extend ActiveSupport::Concern

  AGENT_CREATE_ACTIONS = %w[create bulk_create].freeze

  included do
    before_action :ensure_billing_access
    before_action :ensure_agent_limit, if: -> { controller_name == 'agents' && AGENT_CREATE_ACTIONS.include?(action_name) }
  end

  private

  def ensure_billing_access
    return if billing_exempt?

    account = Current.account
    return if account.nil?

    # No subscription and no trial configured yet (e.g. right after deployment): don't lock
    subscription = Billing::TrialStarter.subscription_for(account)
    return if subscription.nil? || subscription.accessible?

    render json: {
      error: 'subscription_required',
      message: 'This account has no active subscription.'
    }, status: :payment_required
  end

  # A pre-flight so the request is refused with a clear message before Chatwoot starts creating the user.
  # The gate itself is the AccountUser validation (Billing::AgentLimit), which is the one that holds a lock;
  # this check deliberately does not, because it runs outside any transaction.
  def ensure_agent_limit
    account = Current.account
    return unless Billing::ResourceLimit.reached?(account, :agents)

    render json: {
      error: 'plan_limit_reached',
      message: Billing::ResourceLimit.message(:agents, Billing::Entitlements.limit(account, :agents))
    }, status: :unprocessable_entity
  end

  def billing_exempt?
    is_a?(Api::V1::Accounts::BillingController)
  end
end
