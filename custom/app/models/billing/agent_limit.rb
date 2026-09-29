# frozen_string_literal: true

# Validation added to AccountUser by config/initializers/billing.rb
# (every agent / administrator of an account is an AccountUser)
module Billing::AgentLimit
  extend ActiveSupport::Concern

  included do
    validate :billing_agent_limit, on: :create
  end

  private

  def billing_agent_limit
    return if account.nil?
    return unless Billing::PlanLimits.reached?(account, :agents, account.account_users.count)

    errors.add(:base, Billing::PlanLimits.message(account, :agents))
  end
end
