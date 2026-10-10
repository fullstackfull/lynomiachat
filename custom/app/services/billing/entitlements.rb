# frozen_string_literal: true

# THE one place that answers "may account X do Y right now?" (docs/p11/03-plans-entitlements.md).
#
# Nothing else in the product should compare a plan name, read billing_plans.features directly, or decide a
# commercial question from the frontend. Those are the two failures this service exists to prevent: scattered
# `if account.plan == 'pro'`, and a capability that is only hidden rather than refused.
#
# PRECEDENCE, highest first. Each step is a deliberate answer to a different question:
#
#   1. INSTALLATION / SYSTEM        A feature the installation does not offer, or one BillingPlan::SYSTEM_FEATURES
#                                   protects, is never a commercial question. Plans cannot sell or withhold it.
#   2. ACCOUNT OVERRIDE             An operator's explicit, audited, reasoned decision for this one account.
#                                   It wins over the plan, which is the point of having it.
#   3. PLAN ENTITLEMENT             What the subscription bought.
#   4. DEFAULT                      Today's behaviour. This is what every account gets while commercial
#                                   enforcement is off, and it is why deploying this changes nothing.
#
# WHERE THE EFFECTIVE STATE LIVES, and why this is not a second system:
# plan features are applied by writing them into the account's own feature flags (Billing::FeatureSync), and
# that remains the single store of effective state -- every existing `feature_enabled?` check in the product
# keeps working untouched. What this service adds is the override layer above it, and the ability to say WHICH
# layer produced the answer, which is what `source` is for and what the flags alone could never tell you.
module Billing::Entitlements
  module_function

  # @return [Boolean]
  def allowed?(account, capability)
    return false if account.nil?
    return account.feature_enabled?(capability) if system_capability?(capability)

    override = override_for(account, :feature, capability)
    return override.enabled if override

    account.feature_enabled?(capability)
  end

  # Which layer produced the answer: :system, :override, :plan or :default.
  # This is the question the feature flags cannot answer on their own, and the reason an operator's deliberate
  # enablement used to be indistinguishable from a plan's -- and therefore silently reverted by the next sync.
  def source(account, capability)
    return :system if system_capability?(capability)
    return :override if override_for(account, :feature, capability)
    return :plan if plan_for(account)&.feature_included?(capability)

    :default
  end

  # nil means unlimited. An override wins; otherwise the plan's ceiling; otherwise no ceiling.
  def limit(account, resource)
    override = override_for(account, :limit, resource)
    return override.limit_value if override

    plan_for(account)&.limit_for(resource)
  end

  # A plan that names no channels denies none. That is the backward-compatible default every existing plan
  # and account already has, so nothing is gated until an operator fills the list in.
  def channel_allowed?(account, channel_type)
    return false if account.nil?

    override = override_for(account, :channel, channel_type.to_s)
    return override.enabled if override

    entitled = plan_for(account)&.channel_entitlements
    return true if entitled.blank?

    entitled.include?(channel_type.to_s)
  end

  # Every override an operator has granted this account, for the console. Lapsed ones are excluded.
  def overrides(account)
    return BillingEntitlementOverride.none if account.nil?

    account.billing_entitlement_overrides.live.order(:kind, :name)
  end

  def plan_for(account)
    subscription = account&.billing_subscription
    return nil if subscription.nil?
    # An unusable subscription sells nothing. While enforcement is off nothing is unusable (see
    # BillingSubscription#accessible?), which is what keeps this inert during rollout.
    return nil unless subscription.accessible?

    subscription.plan
  end

  def system_capability?(capability)
    BillingPlan::SYSTEM_FEATURES.include?(capability.to_s)
  end

  def override_for(account, kind, name)
    return nil if account.nil?

    account.billing_entitlement_overrides.live.for_capability(kind, name.to_s).first
  end
end
