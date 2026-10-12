# Operator state on an operational signal (docs/product-refinement/07-operations-control-center-v2.md).
#
# WHY THIS IS NOT ON THE SIGNAL'S EXISTING TWO STATES
#
# `Operations::Signal` deliberately has exactly two states -- open and resolved -- because a signal is a FACT
# the product observed, and only another observation may change it. Its own header says a problem that stopped
# being reported is not a problem that was fixed, which is why nothing expires a signal on a timer.
#
# That rule is kept. These columns are a SECOND, separate layer: what an OPERATOR has decided about a signal
# that is still open. Acknowledging does not resolve anything and suppressing does not hide a fact -- both
# record a human judgement alongside the observation, and the observation stays exactly as it was.
#
#   acknowledged_*   "I have seen this and I am on it." Removes it from the unacknowledged queue, nothing else.
#   suppressed_until "This is known and noisy; stop ranking it until this time." Time-bounded ON PURPOSE: an
#                    indefinite mute is how a real problem disappears. A reason is required at the service.
#
# Both are cleared by `resume`, and both are IGNORED once the signal resolves, because they describe the
# operator's handling of an open problem.
#
# NULLABLE AND NO FOREIGN KEY on the actor columns, matching the `audits` table's own arrangement: an operator's
# user row may be deleted and the handling record must survive it. The name is snapshotted in
# operations_signal_events instead, which is where a reader looks for who did what.
#
# ROLLBACK drops the five columns and the two indexes. No data outside them depends on it; the signals
# themselves are untouched.
class AddOperatorStateToOperationsSignals < ActiveRecord::Migration[7.1]
  def change
    change_table :operations_signals, bulk: true do |t|
      t.datetime :acknowledged_at
      t.bigint :acknowledged_by_id
      t.datetime :suppressed_until
      t.string :suppression_reason, limit: 500
      t.bigint :suppressed_by_id
    end

    # The attention queue's two defining predicates. Partial on `resolved_at IS NULL` for the same reason every
    # other index on this table is: the queue only ever reads open signals, and a resolved signal is history.
    add_index :operations_signals, %i[acknowledged_at last_seen_at],
              name: 'index_operations_signals_on_unacknowledged',
              order: { last_seen_at: :desc },
              where: 'resolved_at IS NULL AND acknowledged_at IS NULL'

    add_index :operations_signals, :suppressed_until,
              name: 'index_operations_signals_on_suppressed',
              where: 'resolved_at IS NULL AND suppressed_until IS NOT NULL'
  end
end
