# frozen_string_literal: true

# Grants or revokes one commercial exception for one account, and records who did it
# (docs/p11/03-plans-entitlements.md).
#
# The only writer of BillingEntitlementOverride, for the same reason Operations::SignalRecorder is the only
# writer of a signal: the audit row is not optional, and a second caller that forgot it would leave an
# exception nobody can explain. Every grant is one Custom::AuditLog row against the account, which puts it on
# the account's own audit trail with no new reader -- the same shape P10 used for the contact merge and
# Commerce::AuditTrail uses for a store connection.
class Billing::OverrideGrant
  class Error < StandardError; end

  AUDIT_GRANTED = 'billing.override_granted'
  AUDIT_REVOKED = 'billing.override_revoked'

  # actor: the SuperAdmin who pressed the button. SuperAdmin is a User subclass on the users table
  # (app/models/super_admin.rb), which is why `granted_by` is a plain User reference and not a second
  # polymorphic actor column.
  def initialize(account, actor: nil)
    @account = account
    @actor = actor
  end

  # kind: :feature | :limit | :channel. `value` is the answer the kind calls for -- a boolean for a feature or
  # channel override, an integer ceiling for a limit override -- which is the shape
  # BillingEntitlementOverride#value_matches_kind enforces.
  def grant!(kind:, name:, reason:, value:, expires_at: nil)
    raise Error, 'An account is required' if @account.nil?

    override = @account.billing_entitlement_overrides.find_or_initialize_by(kind: kind, name: name.to_s)
    raise Error, "#{override.name} is not a capability a plan can sell" if override.kind_feature? && !sellable_feature?(override.name)

    override.assign_attributes(answer_for(override, value).merge(reason: reason, expires_at: expires_at, granted_by: @actor))
    save_and_apply(override)

    audit(AUDIT_GRANTED, override.previously_new_record? ? 'create' : 'update', audit_payload(override))
    override
  end

  def revoke!(override)
    raise Error, 'That override belongs to another account' unless override.account_id == @account&.id

    snapshot = audit_payload(override)
    BillingEntitlementOverride.transaction do
      override.destroy!
      apply_feature(override.name, plan_includes?(override.name)) if override.kind_feature?
    end
    audit(AUDIT_REVOKED, 'destroy', snapshot)
    true
  end

  private

  # The kind decides which column carries the answer, per BillingEntitlementOverride#value_matches_kind.
  def answer_for(override, value)
    override.kind_limit? ? { limit_value: value, enabled: nil } : { enabled: value, limit_value: nil }
  end

  # The row and the flag it implies move together or not at all.
  def save_and_apply(override)
    BillingEntitlementOverride.transaction do
      raise Error, override.errors.full_messages.to_sentence unless override.save

      apply_feature(override.name, override.enabled) if override.kind_feature?
    end
  end

  # A feature override has to CHANGE the capability, not merely record an intention. The account's own feature
  # flags are the effective state the whole product reads (docs/p11/02-commercial-architecture.md §2), so the
  # grant writes them; Billing::FeatureSync then refuses to move an overridden capability, which is what makes
  # the write survive the next plan sync. Without this the console's "switch one capability on or off for this
  # account regardless of its plan" was false: the row only exempted the capability from future syncs.
  def apply_feature(name, enabled)
    enabled ? @account.enable_features!(name) : @account.disable_features!(name)
  end

  # What the subscription would have said. Revoking an exception returns the account to its plan, which means
  # writing the plan's answer back into the flags rather than leaving whatever the exception set.
  def plan_includes?(name)
    Billing::Entitlements.plan_for(@account)&.feature_included?(name) || false
  end

  # A plan cannot sell a system, internal, deprecated or Enterprise-licensed capability, so an override on one
  # would be a flag write with no commercial meaning -- and `disable_features!` on a system flag would break
  # the installation. BillingPlan.assignable_features is the same list the plan form offers.
  def sellable_feature?(name)
    BillingPlan.assignable_features.pluck('name').include?(name)
  end

  def audit(event, action, payload)
    Custom::AuditLog.create!(
      auditable: @account, associated: @account, user: @actor,
      action: action, comment: event, audited_changes: payload
    )
  rescue StandardError => e
    # The exception itself is the thing the customer's access depends on; a failed audit write must not undo
    # it. Loud in the log instead, same reasoning as the P10 merge audit.
    Rails.logger.error("[Billing] Could not record #{event} for account #{@account&.id}: #{e.class}")
  end

  # Ids, names, numbers and a reason an operator typed. No secret can reach this.
  def audit_payload(override)
    {
      'kind' => override.kind,
      'name' => override.name,
      'enabled' => override.enabled,
      'limit_value' => override.limit_value,
      'reason' => override.reason,
      'expires_at' => override.expires_at&.iso8601
    }
  end
end
