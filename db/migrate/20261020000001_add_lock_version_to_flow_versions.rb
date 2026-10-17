class AddLockVersionToFlowVersions < ActiveRecord::Migration[7.2]
  # CONCURRENT EDITING, WHICH THE DRAFT SAVE HAD NO DEFENCE AGAINST.
  #
  # Flows::Versions#save! did `version.update!(graph: graph)` with no precondition, so two people
  # editing the same flow was a silent lost update: the second save overwrote the first with a
  # graph built from a view of the flow that no longer existed, and neither editor was told.
  #
  # `lock_version` is Rails' own optimistic locking column -- its mere presence makes every
  # ActiveRecord update of this table a conditional `UPDATE ... WHERE lock_version = ?`, so the
  # check is done by the database rather than by a read-then-compare that races. The editor sends
  # back the value it loaded; a save against a draft that has moved raises StaleObjectError and
  # the API answers 409 instead of destroying the other person's work.
  def change
    add_column :flow_versions, :lock_version, :integer, default: 0, null: false
  end
end
