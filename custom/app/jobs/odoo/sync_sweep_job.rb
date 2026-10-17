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
# IT RUNS EVERY FIVE MINUTES, from config/schedule.yml. An earlier version of this file left it unscheduled so
# that nothing could start synchronising on deployment -- but that made the retry schedule a record of intent
# rather than something that happens: a row that failed transiently got a `run_after`, and nothing ever came
# back to read it. The deployment concern it was protecting against does not arise, and nothing about this
# sweep can start an export on its own:
#
#   * it creates no work. Rows exist only because Odoo::EventRecorder recorded one, and that returns [] unless
#     Odoo::DestinationProfile.active finds an ENABLED destination. A fresh installation has no profile, so
#     the sweep's query matches nothing on every run.
#   * it decides nothing. Each row it finds goes to Odoo::SyncJob, and Odoo::SyncRunner blocks the row with
#     `destination_not_enabled` if synchronisation has since been switched off.
class Odoo::SyncSweepJob < ApplicationJob
  # `scheduled_jobs`, matching the queue config/schedule.yml pushes it onto, so a sweep enqueued by hand from
  # a console behaves the same way as the scheduled one. The export work itself stays on `low`
  # (Odoo::SyncJob): finding the work is cheap, doing it is what must not compete with a conversation.
  queue_as :scheduled_jobs
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
