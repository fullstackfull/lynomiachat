# What each attempt at one sync event actually did (docs/odoo/02-architecture.md §6).
#
# WHY PER-ATTEMPT ROWS. An accounting write is attempted at most once per attempt row -- the same rule as
# Commerce::ActionJob, where "a write is sent at most once, and a lost answer is reconciled by reading the
# store, not by sending again". That rule is only enforceable if there is a durable record of the attempt that
# survives the worker dying between sending the request and reading the answer. Without these rows, a crash
# mid-write is indistinguishable from a write that never happened, and the recovery for the two is opposite.
#
# `outcome` carries that distinction explicitly: `not_sent` means the request provably never reached Odoo (DNS,
# refused connection, connect timeout) and is safe to repeat, while `unknown_outcome` means Odoo may have acted
# and the next step is to SEARCH for our stamp, never to write again. Commerce::HttpClient#send_once already
# draws the same line for store APIs.
#
# No provider message is stored, only a class, a code and a bounded scrubbed reason -- the same rule as
# BillingWebhookEvent#failed! ("only a classification, never the provider's message").
class CreateOdooSyncAttempts < ActiveRecord::Migration[7.2]
  def change
    create_table :odoo_sync_attempts do |t|
      t.references :odoo_sync_event, null: false, foreign_key: true, index: false

      t.integer :attempt_number, null: false
      # succeeded / permanent / transient / needs_review / not_sent / unknown_outcome.
      t.string :outcome, null: false

      # What was asked of Odoo. Named explicitly so a diagnostic can say "create on account.move failed"
      # instead of "sync failed", which is the difference between a usable error screen and a shrug.
      t.string :odoo_model
      t.string :odoo_method
      t.integer :odoo_record_id

      t.string :error_class
      t.string :error_code
      # Bounded and credential-scrubbed before it is written. Odoo's own ValidationError text is the one thing
      # that tells an operator WHICH field their journal configuration got wrong, so it is worth carrying -- but
      # it is carried through the same scrub Operations::SignalRecorder applies, never raw.
      t.string :reason, limit: 500

      t.integer :duration_ms
      t.datetime :started_at, null: false

      # No updated_at: an attempt is a fact about a moment and is never revised.
      t.datetime :created_at, null: false
    end

    # One row per attempt number per event, so a double-recorded attempt is a failed insert rather than a
    # second write nobody counted.
    add_index :odoo_sync_attempts, [:odoo_sync_event_id, :attempt_number],
              unique: true, name: 'uniq_odoo_sync_attempt_per_event'
    add_index :odoo_sync_attempts, [:outcome, :created_at], name: 'index_odoo_sync_attempts_on_outcome'
  end
end
