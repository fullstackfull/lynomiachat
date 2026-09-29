# frozen_string_literal: true

# Reads the agents / inboxes limits of the account's current plan.
# nil limit (empty in the plan form) = unlimited.
module Billing::PlanLimits
  module_function

  def limit_for(account, key)
    account&.billing_subscription&.plan&.limit_for(key)
  end

  def reached?(account, key, current_count)
    limit = limit_for(account, key)
    !limit.nil? && current_count >= limit
  end

  def message(account, key)
    limit = limit_for(account, key)
    "Your plan allows up to #{limit} #{key}. Upgrade your plan to add more."
  end
end
