# The work queue: one row per thing that happened in Stripe which may need an accounting document
# (docs/odoo/02-architecture.md §6).
#
# WHY A TABLE AND NOT JUST A SIDEKIQ JOB. A Stripe webhook must return in milliseconds and must not depend on
# Odoo being reachable, so the webhook's whole contribution is to insert one of these rows. The queue is then
# drained by a worker that may fail, be retried, be blocked by an unconfigured destination, or need a human --
# seven states a Sidekiq job cannot express and an operator cannot read.
#
# `dedup_key` is scoped the same way as a document mapping's idempotency key, so a Stripe redelivery, a second
# webhook about the same object, and a historical backfill covering a period that live sync already handled all
# collapse onto one row instead of producing a second accounting document.
class CreateOdooSyncEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :odoo_sync_events do |t|
      t.references :odoo_destination_profile, null: false, foreign_key: true, index: false
      t.integer :account_id

      t.string :provider, null: false, default: 'stripe'
      # The Stripe event id when this came from a webhook, so a row can be traced back to the delivery that
      # produced it. Null for a backfill or an operator-requested retry, which have no event behind them.
      t.string :provider_event_id
      t.string :event_type, null: false
      t.string :provider_object_type, null: false
      t.string :provider_object_id, null: false

      # webhook / backfill / operator. The brief requires a historical import to be impossible to confuse with
      # live synchronisation, and this is the column that keeps them distinguishable in every screen and query.
      t.string :origin, null: false

      # pending / processing / synchronized / retrying / failed / blocked / needs_review.
      t.integer :state, null: false, default: 0
      t.integer :attempts_count, null: false, default: 0
      # When this row becomes eligible again. Backoff is a timestamp rather than a Sidekiq retry schedule
      # because an operator has to be able to see WHEN the next attempt is, and to bring it forward.
      t.datetime :run_after
      # Claimed by a worker. A stale claim is what a sweep looks for: a worker killed mid-flight leaves this
      # set and `state` processing, and nothing else would ever notice.
      t.datetime :claimed_at
      t.datetime :completed_at

      t.string :last_error_class
      t.string :blocked_reason
      t.string :dedup_key, null: false

      t.timestamps
    end

    add_index :odoo_sync_events, :dedup_key, unique: true, name: 'uniq_odoo_sync_event_dedup_key'
    # The drain query: what is due now, oldest first.
    add_index :odoo_sync_events, [:state, :run_after], name: 'index_odoo_sync_events_on_state_and_run_after'
    add_index :odoo_sync_events, [:odoo_destination_profile_id, :created_at], name: 'index_odoo_sync_events_on_profile'
    add_index :odoo_sync_events, [:account_id, :created_at], name: 'index_odoo_sync_events_on_account'
    # The Errors screen, which is only ever interested in the rows that are not fine.
    add_index :odoo_sync_events, :updated_at, where: 'state IN (4, 5, 6)', name: 'index_odoo_sync_events_on_unhealthy'
  end
end
