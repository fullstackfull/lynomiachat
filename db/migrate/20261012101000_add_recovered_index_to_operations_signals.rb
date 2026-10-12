# "What recovered recently" needs an index, because it is the first read of this table that asks about RESOLVED
# rows (docs/product-refinement/10-operations-ui.md §overview). Every existing index on operations_signals is
# partial on `resolved_at IS NULL` -- they serve the open set and are useless to this query, which would
# otherwise scan the table and get slower with every incident ever closed.
#
# Partial the other way and ordered the way the feed reads it, so the newest recoveries are the first rows the
# planner touches.
class AddRecoveredIndexToOperationsSignals < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :operations_signals, :resolved_at, order: { resolved_at: :desc },
                                                 where: 'resolved_at IS NOT NULL',
                                                 name: 'index_operations_signals_on_recovered',
                                                 algorithm: :concurrently
  end
end
