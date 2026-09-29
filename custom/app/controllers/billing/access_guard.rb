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

    subscription = account.billing_subscription
    # Billing not set up yet (right after deployment): don't lock anyone
    return if subscription.nil? && !Billing::TrialStarter.configured?

    subscription ||= Billing::TrialStarter.new(account).perform
    return if subscription.usable?

    render json: {
      error: 'subscription_required',
      message: 'This account has no active subscription.'
    }, status: :payment_required
  end

  def ensure_agent_limit
    account = Current.account
    return unless Billing::PlanLimits.reached?(account, :agents, account.account_users.count)

    render json: {
      error: 'plan_limit_reached',
      message: Billing::PlanLimits.message(account, :agents)
    }, status: :unprocessable_entity
  end

  def billing_exempt?
    is_a?(Api::V1::Accounts::BillingController)
  end
end
