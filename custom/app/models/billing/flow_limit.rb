# frozen_string_literal: true

# Validation added to AgentBot by config/initializers/billing.rb.
#
# ON THE MODEL, NOT IN THE CONTROLLER, for the same reason the agent and inbox ceilings are:
# AgentBot creation is the shared point downstream of every way a flow comes into existence --
# the Flow Builder's own create, the Studio's duplicate, a template, a console. A check written
# at one of those is a check the next one forgets.
#
# ONLY FLOW BOTS. A webhook bot is an integration's callback, not a flow a merchant authored,
# and nothing sells those by the dozen. `bot_type` cannot change afterwards
# (Custom::AgentBot#bot_type_unchanged), so a bot created under the ceiling cannot become a flow
# that would have exceeded it -- which is why this runs on create only and needs no counterpart
# on update.
module Billing::FlowLimit
  extend ActiveSupport::Concern

  included do
    validate :billing_flow_limit, on: :create, if: :flow?
  end

  private

  def billing_flow_limit
    return if account.nil?

    limit = Billing::ResourceLimit.exceeded(account, :flows)
    return if limit.nil?

    errors.add(:base, Billing::ResourceLimit.message(:flows, limit,
                                                     Billing::Entitlements.limit_source(account, :flows)))
  end
end
