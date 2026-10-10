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
    answer = override.kind_limit? ? { limit_value: value, enabled: nil } : { enabled: value, limit_value: nil }
    override.assign_attributes(answer.merge(reason: reason, expires_at: expires_at, granted_by: @actor))
    raise Error, override.errors.full_messages.to_sentence unless override.save

    audit(AUDIT_GRANTED, override.previously_new_record? ? 'create' : 'update', audit_payload(override))
    override
  end

  def revoke!(override)
    raise Error, 'That override belongs to another account' unless override.account_id == @account&.id

    snapshot = audit_payload(override)
    override.destroy!
    audit(AUDIT_REVOKED, 'destroy', snapshot)
    true
  end

  private

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
