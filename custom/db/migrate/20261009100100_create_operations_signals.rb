# Lynomia Operations: the installation's first durable record of an operational problem
# (docs/p9/04-operations-center.md).
#
# Why this table has to exist. Before it, nothing operational was queryable. Channel health lived entirely in
# Redis under two un-expiring keys (app/models/concerns/reauthorizable.rb:20-72,
# lib/redis/redis_keys.rb:68-69); an IMAP inbox with a rotated password wrote one log line per poll and NOTHING
# to Postgres (app/jobs/inboxes/fetch_imap_emails_job.rb:14-16) while silently stopping its own polling
# (:26); webhook delivery failures and Sidekiq queue depth were log lines only
# (custom/app/services/lynomia/operator_log.rb). "Show me every broken inbox across all accounts, newest first"
# was not expressible against anything that existed.
#
# ONE ROW PER DISTINCT OPEN PROBLEM, not one row per occurrence. A failing inbox polled every minute is one row
# with a rising `occurrences`, not 1,440 rows a day. That is what the partial unique index enforces, and the same
# key is the dedup key for the support-case bridge, so "is there already a case for this?" is a column read
# rather than a heuristic.
#
# WHAT IT DELIBERATELY DOES NOT HOLD: no provider response body, no webhook payload, no URL with a query token,
# no header, no credential. `reason` is one sanitized line and `detail` carries allow-listed keys holding ids,
# codes and counts only -- enforced in one place, Operations::SignalRecorder.
class CreateOperationsSignals < ActiveRecord::Migration[7.2]
  def change
    create_table :operations_signals do |t|
      # Nullable: a queue or installation signal belongs to no account.
      t.references :account, index: false, foreign_key: { on_delete: :cascade }
      t.string :source, null: false
      t.string :signal, null: false
      t.integer :severity, null: false, default: 1
      # The affected record, as a string column with an allow-list validation rather than a Rails polymorphic
      # association: nothing in this repository constrains a polymorphic type column, and an unconstrained one is
      # a class name the caller chooses.
      t.string :subject_type
      t.bigint :subject_id
      t.string :reason
      t.jsonb :detail, null: false, default: {}
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.integer :occurrences, null: false, default: 1
      t.datetime :resolved_at
      t.references :support_ticket, index: false, foreign_key: { on_delete: :nullify }
      t.timestamps
    end

    add_signal_indexes
  end

  private

  def add_signal_indexes
    # The identity of an OPEN problem. COALESCE rather than the bare columns because Postgres treats NULLs as
    # distinct in a unique index, so two installation-wide rows (account_id NULL, subject NULL) would both be
    # accepted and the dedup this table exists for would not hold where it matters most.
    add_index :operations_signals,
              "COALESCE(account_id, 0), source, COALESCE(subject_type, ''), COALESCE(subject_id, 0), signal",
              unique: true, where: 'resolved_at IS NULL', name: 'index_operations_signals_on_open_identity'
    # The console's two reads: the installation-wide issue feed, and one account's open issues.
    add_index :operations_signals, :last_seen_at, order: { last_seen_at: :desc },
                                                  where: 'resolved_at IS NULL', name: 'index_operations_signals_on_open_feed'
    add_index :operations_signals, [:account_id, :last_seen_at], order: { last_seen_at: :desc },
                                                                 where: 'resolved_at IS NULL', name: 'index_operations_signals_on_account_open'
    # The bridge's reverse lookup: which signals does this case cover.
    add_index :operations_signals, :support_ticket_id, where: 'support_ticket_id IS NOT NULL',
                                                       name: 'index_operations_signals_on_support_ticket'
  end
end
