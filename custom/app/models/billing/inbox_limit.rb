# frozen_string_literal: true

# Validation added to Inbox by config/initializers/billing.rb
# Applies to every way of creating an inbox (website, email, WhatsApp, ...).
module Billing::InboxLimit
  extend ActiveSupport::Concern

  included do
    validate :billing_inbox_limit, on: :create
  end

  private

  def billing_inbox_limit
    return if account.nil?
    return unless Billing::PlanLimits.reached?(account, :inboxes, account.inboxes.count)

    errors.add(:base, Billing::PlanLimits.message(account, :inboxes))
  end
end
