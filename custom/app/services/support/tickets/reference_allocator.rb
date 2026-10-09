# Allocates the next per-account support-case reference (docs/p9/01-architecture.md §3).
#
# Race safety comes from a Postgres transaction-scoped advisory lock keyed on (namespace, account_id). Two
# simultaneous creates in the same account serialise on it; creates in different accounts never touch each other;
# and the lock is released by the transaction, so a crashed request cannot leave it held.
#
# `MAX(reference_number) + 1` rather than a sequence is deliberate. A per-account sequence would mean copying
# Conversation#display_id's mechanism -- a trigger on accounts, a trigger on this table, a backfill for every
# existing account because the sequences are absent from db/schema.rb, and a line in
# Account#remove_account_sequences -- for an object a human creates a few times an hour.
#
# Numbers are not reused: a case is closed, never destroyed, and the API exposes no delete.
module Support::Tickets::ReferenceAllocator
  # Any stable 32-bit value works; hashtext of a fixed string keeps it readable in pg_locks.
  LOCK_NAMESPACE_SQL = "hashtext('support_tickets_reference')".freeze

  module_function

  def next_for(account_id)
    account_id = Integer(account_id)
    connection = Support::Ticket.connection
    connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE_SQL}, #{connection.quote(account_id)})")
    current = connection.select_value(
      Support::Ticket.unscoped.where(account_id: account_id).select('MAX(reference_number)').to_sql
    )
    current.to_i + 1
  end
end
