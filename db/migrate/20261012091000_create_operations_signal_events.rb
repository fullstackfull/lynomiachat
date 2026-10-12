# The incident lifecycle of one operational signal (docs/product-refinement/07-operations-control-center-v2.md).
#
# WHY THIS IS NOT THE AUDIT LOG
#
# `Custom::AuditLog` answers "who changed product data". This answers "what happened to this incident". They
# overlap for exactly one kind of row -- an operator action -- and they are still different questions:
#
#   audit      every mutation in the product, by actor, for accountability. An operator acknowledging a signal
#              writes one, and it is filed installation-wide with no `associated`.
#   timeline   one signal's story in order: first detected, recurred 40 times, acknowledged by Hisham,
#              suppressed for a day because Meta was down, resumed, recovered. Machine events as well as human
#              ones, which the audit log does not and should not carry.
#
# An operator diagnosing a recurring problem reads the timeline. A security review reads the audit. Writing an
# operator action to both is deliberate duplication of one row, not of the two systems.
#
# WHAT MAY GO IN `detail`
# Scalars from an allow-list, enforced by the writer, for the same reason Operations::SignalRecorder enforces
# one: this table is read by a human on a screen, and a provider response body has no business reaching it.
# There is no provider payload, no header, no token -- and the writer is the only way in.
#
# `actor_name` is snapshotted so a timeline stays attributable after the operator's user row is deleted, which
# is the same rule Custom::AuditLog#capture_actor_name applies to every audit row.
#
# ROLLBACK drops the table. Signals are untouched; only their history is lost, which is why the audit log
# carries the operator actions independently.
class CreateOperationsSignalEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :operations_signal_events do |t|
      t.references :operations_signal, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :event_type, null: false
      t.bigint :actor_id
      t.string :actor_name, limit: 255
      t.string :reason, limit: 500
      t.jsonb :detail, default: {}, null: false
      t.datetime :created_at, null: false
    end

    # The only read this table serves: one signal's history, oldest first.
    add_index :operations_signal_events, %i[operations_signal_id created_at],
              name: 'index_operations_signal_events_on_signal_and_created_at'
  end
end
