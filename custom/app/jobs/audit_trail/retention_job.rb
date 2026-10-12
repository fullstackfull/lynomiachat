# DECISION 5. The audit trail records always and is bounded by time, not by a feature flag.
#
# CAPTURE IS NOT GATED, AND THIS JOB DOES NOT CHANGE THAT. `audit_logs` gates reading
# (custom/app/services/audit_trail/query.rb:52); every writer -- the twelve Custom::Audit::* modules, the seven
# direct services and the `audited` macro itself -- writes unconditionally. That is the security property: a
# trail an audited party can switch off from their own settings page is not a trail. What was missing was any
# bound at all, so the table grew without limit on behalf of accounts that hold no entitlement to read it.
#
# THE WINDOW IS A SYSTEM SETTING, NOT A PLAN FEATURE AND NOT A BROWSER SETTING. `AUDIT_LOG_RETENTION_DAYS`
# (config/installation_config.yml) defaults to 365 and is changed by an operator on the Super Admin general
# settings form (`/super_admin/app_config?config=general`), which is why the key is listed in
# `SuperAdmin::AppConfigsController::GENERAL_CONFIGS` -- that list is an allow-list and `create` silently drops
# any key absent from it, so without the entry there was no way to change this at all. Seeding the installation
# config works too. It is read on every run, so a change takes effect on the next sweep with no deploy. No
# account, administrator or agent can reach it.
#
# IDEMPOTENT AND SAFE TO OVERLAP. The deletable set is defined entirely by a cutoff computed from the clock, so
# a second run finds whatever the first left and nothing else; two concurrent runs race only on rows that are
# already condemned, and the loser deletes nothing. There is no advisory lock because there is nothing for one
# to protect -- which is also why the sibling sweep (custom/app/jobs/commerce/action_sweep_job.rb) has none.
#
# IT CANNOT REACH A ROW INSIDE THE WINDOW. The predicate is a strict `<` against a cutoff on a UTC day
# boundary, so the effective retention is the configured days plus up to one day -- erring longer, never
# shorter. A row whose `created_at` is NULL (the column is nullable on the shared upstream table) matches no
# comparison and is therefore never deleted.
class AuditTrail::RetentionJob < ApplicationJob
  queue_as :housekeeping

  CONFIG_KEY = 'AUDIT_LOG_RETENTION_DAYS'.freeze
  DEFAULT_DAYS = 365

  # An operator can set this value, and 0 or a negative would mean "delete the whole trail". It is refused
  # rather than obeyed, loudly, because the loss is not recoverable and a value that low is a typo rather than
  # an intention. Thirty days is the floor: short enough to be a real choice, long enough that no plausible
  # typo lands inside it.
  MIN_DAYS = 30

  # Deliberately small for a table this wide: `audited_changes` is jsonb, so a batch is held in memory as ids
  # and deleted by id, and a long transaction on `audits` would block the one table every product action
  # writes to.
  BATCH_SIZE = 1_000

  # A ceiling on one run rather than on the job, so the first sweep of a table that has never been bounded
  # finishes in a predictable time and the remainder is taken tomorrow. When it stops early it says so.
  MAX_PER_RUN = 200_000

  def perform
    days = retention_days
    return if days.nil?

    cutoff = cutoff_for(days)
    deleted = delete_before(cutoff)

    Lynomia::OperatorLog.info(:AUDIT_RETENTION_SWEEP, retention_days: days, cutoff: cutoff.iso8601,
                                                      deleted: deleted, capped: deleted >= MAX_PER_RUN)
  end

  private

  # Nil means "do not sweep", and every nil path says why. Nothing is skipped silently.
  def retention_days
    raw = GlobalConfigService.load(CONFIG_KEY, DEFAULT_DAYS)
    days = Integer(raw, exception: false)

    if days.nil?
      Lynomia::OperatorLog.error(:AUDIT_RETENTION_MISCONFIGURED, config: CONFIG_KEY, reason: 'not_an_integer')
      return nil
    end
    return days if days >= MIN_DAYS

    Lynomia::OperatorLog.error(:AUDIT_RETENTION_MISCONFIGURED, config: CONFIG_KEY, reason: 'below_minimum',
                                                               minimum: MIN_DAYS, configured: days)
    nil
  end

  # UTC, and on a day boundary, so the set a run condemns does not depend on the minute the scheduler fired.
  def cutoff_for(days)
    days.days.ago.utc.beginning_of_day
  end

  # `delete_all` rather than `destroy_all`: an audit row has no callbacks worth running and no dependents, and
  # loading hundreds of thousands of jsonb rows to discard them is the thing to avoid. Batched by id so each
  # statement is bounded and the `created_at` index does the selection.
  def delete_before(cutoff)
    deleted = 0

    loop do
      ids = Custom::AuditLog.where(created_at: ...cutoff).limit(BATCH_SIZE).pluck(:id)
      break if ids.empty?

      deleted += Custom::AuditLog.where(id: ids).delete_all
      break if deleted >= MAX_PER_RUN
    end

    deleted
  end
end
