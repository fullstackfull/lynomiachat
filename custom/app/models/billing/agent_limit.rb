# frozen_string_literal: true

# Validation added to AccountUser by config/initializers/billing.rb
# (every agent / administrator of an account is an AccountUser)
#
# AccountUser creation is the single shared choke point for adding a person to an account -- an invitation, a
# bulk invite, the Platform API and a reactivation all pass through it -- which is why the rule lives here and
# not in each of those paths. The counting and the locking are Billing::ResourceLimit's.
module Billing::AgentLimit
  extend ActiveSupport::Concern

  included do
    validate :billing_agent_limit, on: :create
  end

  private

  def billing_agent_limit
    return if account.nil?

    limit = Billing::ResourceLimit.exceeded(account, :agents)
    return if limit.nil?

    errors.add(:base, Billing::ResourceLimit.message(:agents, limit))
  end
end
