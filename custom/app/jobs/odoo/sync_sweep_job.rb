# The safety net under the queue (docs/odoo/02-architecture.md §6).
#
# THREE THINGS NOTHING ELSE WOULD NOTICE:
#
#   1. A row whose backoff has expired. Odoo::SyncJob is enqueued when the work is recorded, not when a retry
#      becomes due, so a `retrying` row sitting past its `run_after` needs somebody to pick it up.
#   2. A worker that died mid-flight. It leaves `state` processing and `claimed_at` set, and the row would
#      stay there for ever -- so a claim older than Odoo::SyncEvent::STALE_CLAIM_AFTER is released back to
#      `retrying`. Released rather than retried on the spot, so it goes through the normal attempt accounting.
#   3. Nothing else. This sweep does not create work, does not import history and does not touch a document.
#
# It is deliberately NOT registered as a recurring job by this change. The brief forbids anything that starts
# synchronising on deployment, and a cron entry that drains a queue the operator has not switched on would do
# exactly that. docs/odoo/06-runbook.md gives the one line to add once a destination is live.
class Odoo::SyncSweepJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  # Bounded so one sweep cannot monopolise a worker on an installation with a long backlog; the next sweep
  # takes the next batch.
  BATCH = 100

  def perform
    release_stale_claims
    Odoo::SyncEvent.due.order(:run_after, :id).limit(BATCH).pluck(:id).each do |id|
      Odoo::SyncJob.perform_later(id)
    end
  end

  private

  # rubocop:disable Rails/SkipsModelValidations -- one UPDATE over a set, with no validation on this table a
  # state transition could violate, and loading each row to save it would be a query per abandoned claim.
  def release_stale_claims
    Odoo::SyncEvent.stale_claims.update_all(state: Odoo::SyncState::STATES[:retrying], claimed_at: nil,
                                            run_after: Time.current, updated_at: Time.current)
  end
  # rubocop:enable Rails/SkipsModelValidations
end
