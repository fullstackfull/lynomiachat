# The one state vocabulary for everything this integration tracks (docs/odoo/02-architecture.md §6).
#
# ONE SET, three tables. A customer mapping, a document mapping and a queued event all answer the same
# question -- "has this been exported, is it on its way, or does it need a human?" -- so they answer it with the
# same words. Three overlapping vocabularies would mean an Errors screen that has to special-case each table
# and an operator who has to learn which "failed" they are looking at.
#
# Integers, not strings, and the ORDER IS LOAD-BEARING: `db/migrate/20261016120300_create_odoo_sync_events.rb`
# indexes `state IN (4, 5, 6)` for the Errors screen, so `failed`, `blocked` and `needs_review` must stay the
# last three and stay contiguous. UNHEALTHY below is the Ruby side of that same predicate; the spec compares
# them so a reordering cannot silently leave the index selecting the wrong rows.
module Odoo::SyncState
  STATES = {
    # Recorded, not yet attempted.
    pending: 0,
    # Claimed by a worker. A row left here with a stale `claimed_at` is a worker that died mid-flight, which is
    # the one case the sweep looks for.
    processing: 1,
    # Written to Odoo and confirmed by reading it back.
    synchronized: 2,
    # A transient failure, waiting for `run_after`. Self-healing, so deliberately NOT one of the unhealthy
    # states: an operator does not need to look at a row that is going to fix itself in ninety seconds.
    retrying: 3,
    # Attempts are exhausted, or the failure is permanent. A human must act.
    failed: 4,
    # Refusing to run: the destination is not configured, not enabled, or the thing this row needs
    # (`post_invoices`, a resolved customer) is switched off. Not an error -- nothing is broken, the answer is
    # "not yet" -- which is why it is distinct from `failed`.
    blocked: 5,
    # Odoo and Lynomia disagree about something only a person can settle: two accounts resolving to one
    # partner, an amount that does not match, a document somebody has edited in Odoo since we wrote it.
    needs_review: 6
  }.freeze

  # What the Errors screen shows, and what the partial index selects.
  UNHEALTHY = %i[failed blocked needs_review].freeze
end
