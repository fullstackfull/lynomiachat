# Two indexes the account audit trail's read surface needs, and did not have.
#
# WHY THIS IS NEEDED
#   1. The settings page's search box restricts the trail by the actor name recorded on the row. That is a
#      substring match -- `username ILIKE '%term%'` -- which no btree can serve, and the predicate is evaluated
#      twice per request: once for the 25-row page and once for the page's unbounded `total_entries`. Without a
#      trigram index that is two sequential passes over the account's whole trail per keystroke the debounce
#      lets through. `pg_trgm` is already enabled and this repository already indexes exactly this kind of
#      search the same way (contacts' name/email/phone, messages' content, tags' lowered name).
#
#   2. The page's type filter is a first-class control, and the existing (associated_type, associated_id,
#      created_at) index cannot satisfy it: Postgres walks that index in `created_at` order, fetches each row
#      from the heap to test `auditable_type`, and discards the ones that do not match -- and the unbounded
#      count applies the same predicate with no LIMIT, so it always reads the account's full partition. With
#      `auditable_type` in the index between the account and the sort column, both the page and the count are
#      served from the index.
#
#   The actor filter (`user_id`) is deliberately NOT given its own composite index. `audits` takes a row for
#   every audited product action, so each index here is a write cost on the busiest path in the product, and
#   the existing (user_id, user_type) index is selective enough for a filter that names one person -- Postgres
#   can bitmap-AND it with the account index. Two new indexes on this table is the budget; the type filter gets
#   one because it is the control people actually use and because it also fixes the count.
#
# HOW
#   CONCURRENTLY, because `audits` is the one table that grows with every product action and an exclusive lock
#   on it would stall every write in the installation. That needs `disable_ddl_transaction!`, and an
#   interrupted CONCURRENTLY build leaves an INVALID index behind, which `deployment/deploy.sh` stage 5 already
#   checks for and refuses to deploy past.
#
# ROLLBACK
#   Reversible: both indexes are dropped concurrently. Dropping them loses no data and only returns the trail's
#   read surface to the speed it has today.
class AddAuditTrailReadIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  ACTOR_NAME_INDEX = 'index_audits_on_username_trgm'.freeze
  TYPE_FILTER_INDEX = 'index_audits_on_associated_and_auditable_type_and_created_at'.freeze

  def up
    unlimit_statement_timeout

    add_index :audits, :username, name: ACTOR_NAME_INDEX, using: :gin, opclass: :gin_trgm_ops,
              algorithm: :concurrently, if_not_exists: true
    add_index :audits, [:associated_type, :associated_id, :auditable_type, :created_at],
              name: TYPE_FILTER_INDEX, algorithm: :concurrently, if_not_exists: true
  end

  def down
    unlimit_statement_timeout

    remove_index :audits, name: ACTOR_NAME_INDEX, algorithm: :concurrently, if_exists: true
    remove_index :audits, name: TYPE_FILTER_INDEX, algorithm: :concurrently, if_exists: true
  end

  private

  # Production sets a statement timeout to protect request-path queries. An index build on the audit table is
  # not a request and must not be killed partway, which is what leaves an INVALID index behind.
  def unlimit_statement_timeout
    execute("SET statement_timeout = '0'")
  end
end
