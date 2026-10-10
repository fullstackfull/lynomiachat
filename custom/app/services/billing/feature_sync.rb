# frozen_string_literal: true

# Applies a plan to an account by writing its features into the account's own feature flags, which keeps every
# existing `feature_enabled?` check in the product working without knowing anything about billing.
#
# Lynomia (docs/p11/03-plans-entitlements.md): two things were wrong here.
#
#   1. The write was unconditional in both directions, so an operator who switched a managed feature on for one
#      account silently lost it at the next plan sync. There was nowhere to say the decision was deliberate.
#      It now skips any capability an operator has overridden, and Billing::Entitlements is what reads those.
#   2. Every failure was swallowed into a log line. A plan change whose entitlement write failed left the
#      account on its old entitlements with no signal anywhere -- not Sentry, not the Operations Center. The
#      failure is now reported, and recorded as an operations signal so it is visible where an operator looks.
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

    managed = BillingPlan.assignable_features.pluck('name') - overridden_capabilities
    included = @plan.features & managed

    @account.enable_features(*included)
    @account.disable_features(*(managed - included))
    @account.save! if @account.changed?
  rescue StandardError => e
    report_failure(e)
  end

  private

  # A capability an operator decided for this account is not the plan's to move.
  def overridden_capabilities
    @account.billing_entitlement_overrides.live.where(kind: :feature).pluck(:name)
  end

  def report_failure(error)
    Rails.logger.error("[Billing] Feature sync failed for account #{@account&.id}: #{error.message}")
    ChatwootExceptionTracker.new(error, account: @account).capture_exception
    Billing::OperationsSignal.record_sync_failure(@account, error)
  end
end
