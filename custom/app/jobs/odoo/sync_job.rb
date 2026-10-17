# One queued accounting export (docs/odoo/02-architecture.md §6).
#
# `retry: false`, and that is not laziness. The retry schedule for an accounting write lives in
# odoo_sync_events.run_after, where an operator can read it and bring it forward; a Sidekiq retry would run
# the same work on a second, invisible schedule and the queue page would be telling a different story from
# the one actually in force. Odoo::SyncRunner classifies every failure it can and writes the next attempt
# time itself, so there is nothing left for Sidekiq to decide.
#
# `queue_as :low`. An accounting document is not latency-sensitive -- nobody is waiting on a screen for it --
# and it must never compete with a conversation being delivered. The queue order in config/sidekiq.yml puts
# `low` below `default`, which is exactly right.
class Odoo::SyncJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  def perform(sync_event_id)
    event = Odoo::SyncEvent.find_by(id: sync_event_id)
    Odoo::SyncRunner.new(event).call if event
  end
end
