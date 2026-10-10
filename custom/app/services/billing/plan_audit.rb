# frozen_string_literal: true

# Records that someone changed what a plan sells (docs/p11/03-plans-entitlements.md).
#
# There is no plan_versions table, and the doc says why. The consequence is that editing a plan's features,
# limits or channel entitlements changes what EVERY subscriber of that plan has, immediately and mid-period.
# The product rule is therefore to create a new plan and move customers to it rather than to edit a plan
# people are paying for -- and because an operator can still edit one, the change is never silent: one audit
# row naming who did it, what moved, and how many paying accounts it moved for.
#
# Price is not in this list and does not need to be: a Stripe Price is immutable, so Billing::PlanSync creates
# a new one and moves subscribers from their next period (Billing::PriceMigrationJob). Nobody is re-charged
# mid-period for a price edit.
class Billing::PlanAudit
  AUDIT_EVENT = 'billing.plan_entitlements_changed'
  ENTITLEMENT_COLUMNS = %w[features limits channel_entitlements].freeze
  BILLED_STATUSES = %w[trialing active past_due].freeze

  # Call right after a successful save, while `previous_changes` still holds the diff.
  # actor: the SuperAdmin who used the console, or the PlatformApp whose token made the call.
  def self.record(plan, actor:)
    changes = plan.previous_changes.slice(*ENTITLEMENT_COLUMNS)
    return if changes.blank?

    Custom::AuditLog.create!(
      auditable: plan, user: actor, action: 'update', comment: AUDIT_EVENT,
      audited_changes: changes.merge('subscribers_affected' => plan.subscriptions.where(status: BILLED_STATUSES).count)
    )
  rescue StandardError => e
    # The plan is already saved; a failed record must not pretend otherwise.
    Rails.logger.error("[Billing] Could not audit the entitlement change on plan #{plan&.id}: #{e.class}")
  end
end
