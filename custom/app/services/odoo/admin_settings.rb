# Every operator write on the Odoo destination, in one audited place (docs/odoo/06-runbook.md).
#
# ONE WRITER, like Billing::OverrideGrant and for the same reason: the audit entry is not optional, and a
# second caller that forgot it would leave a change to a production accounting destination with nobody's name
# on it. Enabling synchronisation, choosing a journal and rotating an API key are all decisions somebody made,
# and the trail has to say who.
#
# THE ACTOR IS PASSED EXPLICITLY. The `audited` gem's Sweeper resolves an actor through Devise's `:user`
# scope, while Super Admin authenticates under `:super_admin`, so an inferred actor here would be nil or the
# wrong person -- the same trap SuperAdmin::OperationsController documents.
#
# NO SECRET EVER REACHES AN AUDIT ROW. `AUDITED_FIELDS` is an allow-list and `credentials` is not on it; a key
# change is recorded as the FACT that the key changed, with no before and no after.
class Odoo::AdminSettings
  class Error < StandardError; end

  AUDIT_UPDATED = 'odoo.destination_updated'.freeze
  AUDIT_ENABLED = 'odoo.sync_enabled'.freeze
  AUDIT_DISABLED = 'odoo.sync_disabled'.freeze
  AUDIT_KEY_CHANGED = 'odoo.api_key_changed'.freeze
  AUDIT_KEY_CLEARED = 'odoo.api_key_cleared'.freeze

  # What an operator may set, and nothing else. A parameter nobody listed cannot reach the record, which is
  # the controller-boundary rule applied one layer in as well.
  PERMITTED = %i[name environment base_url database username company_id company_name journal_id journal_name
                 payment_journal_id payment_journal_name analytic_account_id analytic_account_name
                 default_product_id default_product_name post_invoices register_payments].freeze

  # The subset that goes into an audit entry. Deliberately excludes `credentials` and every display label, so
  # the trail reads as the decisions rather than as a diff of the form.
  AUDITED_FIELDS = %w[name environment base_url database username company_id journal_id payment_journal_id
                      analytic_account_id default_product_id post_invoices register_payments].freeze

  def initialize(profile, actor: nil)
    @profile = profile
    @actor = actor
  end

  # Returns the profile. An empty API key field leaves the stored key alone -- the rule Billing::Settings
  # already applies, because an operator editing a journal must not have to re-paste a credential.
  def update!(params)
    attributes = params.slice(*PERMITTED).to_h.symbolize_keys
    key = params[:api_key].to_s
    @profile.assign_attributes(attributes)
    @profile.api_key = key if key.present?
    changes = @profile.changes.slice(*AUDITED_FIELDS)
    @profile.save!
    audit(AUDIT_UPDATED, 'update', changes) if changes.any?
    audit(AUDIT_KEY_CHANGED, 'update', { 'api_key' => %w[redacted redacted] }) if key.present?
    @profile
  end

  # ENABLING IS GATED ON PROOF, not on a tick. `may_post?` and the capability probe are what the brief's
  # "a successful login is NOT sufficient proof" turns into code: a destination whose draft-creation probe has
  # never passed cannot be switched on at all.
  def enable!
    raise Error, :not_ready unless @profile.status.in?(%i[ready_disabled active])

    @profile.update!(sync_enabled: true, blocked_reason: nil)
    audit(AUDIT_ENABLED, 'update', { 'sync_enabled' => [false, true] })
    @profile
  end

  # Stopping is never gated. An operator who wants the export to stop gets it stopped, immediately, and the
  # queue keeps its rows so nothing is lost -- they simply stay `blocked` until it is enabled again.
  def disable!(reason: nil)
    @profile.update!(sync_enabled: false, blocked_reason: reason.presence)
    audit(AUDIT_DISABLED, 'update', { 'sync_enabled' => [true, false] })
    @profile
  end

  def clear_api_key!
    @profile.clear_api_key!
    audit(AUDIT_KEY_CLEARED, 'update', { 'api_key' => %w[redacted cleared] })
    @profile
  end

  # Stamps what a connection test or capability probe found. Not audited: a read nobody changed anything with
  # is not a decision, and auditing every poll of a Settings page would bury the entries that matter.
  def record_connection_test(result)
    @profile.update!(last_connection_test_at: Time.current, last_connection_result: result)
  end

  def record_capability_proof(result)
    @profile.update!(last_capability_proof_at: Time.current, last_capability_proof: result)
  end

  private

  # `auditable` is the profile and there is no `associated` account: an Odoo destination is installation-wide,
  # so an entry scoped to one account would be wrong and invisible on the trail that should carry it -- the
  # same shape Billing::PlanAudit uses for a plan's entitlements.
  def audit(event, action, payload)
    Custom::AuditLog.create!(auditable: @profile, user: @actor, action: action, comment: event,
                             audited_changes: payload)
  rescue StandardError => e
    # The change is already saved; a failed audit write must not pretend otherwise. Loud in the log instead,
    # the same reasoning as Billing::OverrideGrant.
    Rails.logger.error("[Odoo] Could not audit #{event} on profile #{@profile&.id}: #{e.class}")
  end
end
