# Every ten minutes (config/schedule.yml): settles order action runs whose own jobs were lost, and drops recovery message
# records past their retention (docs/commerce/32-actions-security.md §reconciliation, 30-abandoned-carts.md §retention).
# It never sends an action: a run that never started is failed (nothing reached the store), and a sent run without an
# answer is only reconciled by reading the store.
class Commerce::ActionSweepJob < ApplicationJob
  queue_as :scheduled_jobs

  NEVER_STARTED = 10.minutes
  # Longer than the last reconciliation delay: a run still unresolved by then lost its reconciliation job.
  UNANSWERED = 15.minutes
  RECOVERY_RETENTION = 90.days

  def perform
    fail_never_started
    reconcile_unanswered
    Commerce::ActionRun.where(action_type: Commerce::ActionRun::RECOVERY_MESSAGE, created_at: ...RECOVERY_RETENTION.ago).in_batches.delete_all
  end

  private

  # Accepted, never claimed: its job was lost before anything was sent. A job that still runs later finds it settled.
  def fail_never_started
    Commerce::ActionRun.order_actions.pending.where(created_at: ...NEVER_STARTED.ago).find_each do |run|
      settled = run.with_lock { run.pending? && run.update!(status: :failed, error_code: 'NOT_SENT', completed_at: Time.current) }
      Commerce::AuditTrail.record('commerce.action.failed', auditable: run, user: run.requested_by, changes: run.audit_fields) if settled
    end
  end

  def reconcile_unanswered
    Commerce::ActionRun.order_actions.where(status: %i[running unknown], updated_at: ...UNANSWERED.ago)
                       .where("COALESCE(commerce_action_runs.metadata->>'reconcile', '') <> 'exhausted'").find_each do |run|
      next Commerce::ActionExecutor.new(run).check_stall if run.running? && run.provider_request_id.nil?

      Commerce::ActionReconcileJob.perform_later(run.id)
    end
  end
end
