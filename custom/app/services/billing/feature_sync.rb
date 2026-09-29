# frozen_string_literal: true

# Turns the account's Chatwoot features on/off to match its plan.
# Only features the super admin can choose in a plan are touched;
# internal, premium and system features are left as they are.
class Billing::FeatureSync
  def self.sync_plan!(plan)
    plan.subscriptions.includes(:account).find_each do |subscription|
      new(subscription.account, plan).perform
    end
  end

  def initialize(account, plan)
    @account = account
    @plan = plan
  end

  def perform
    return if @account.nil? || @plan.nil?

    managed = BillingPlan.assignable_features.pluck('name')
    included = @plan.features & managed

    @account.enable_features(*included)
    @account.disable_features(*(managed - included))
    @account.save! if @account.changed?
  rescue StandardError => e
    Rails.logger.error("[Billing] Feature sync failed for account #{@account&.id}: #{e.message}")
  end
end
