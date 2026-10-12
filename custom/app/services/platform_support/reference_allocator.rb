# Allocates the next GLOBAL Platform Support reference
# (docs/platform-support/12-refresh-against-product-refinement.md §1 "Reference allocation").
#
# GLOBAL, NOT PER-ACCOUNT, and that is the deciding argument rather than a side effect. `LYN-000123` on a phone
# call, in an email subject, in a Slack escalation or on a status page resolves to exactly one ticket with no
# "which account?" follow-up. A per-account series needs the account alongside it in every one of those places
# and collides silently across accounts in search.
#
# RACE SAFETY comes from a Postgres transaction-scoped advisory lock on a CONSTANT key, taken before the
# `MAX(reference_number)` read. Two simultaneous creates serialise on it; the lock is released by the
# transaction, so a crashed request cannot leave it held; and `hashtext('platform_support_reference')` is a
# DIFFERENT namespace from the tenant helpdesk's `hashtext('support_tickets_reference')`, so the two allocators
# never contend with each other.
#
# The cost, stated honestly: this serialises ALL platform-ticket creates installation-wide, where the tenant
# allocator serialises only same-account creates. It is free at this scale -- a platform ticket is opened by a
# human a handful of times a day across every customer -- and what it buys is a reference that is true rather
# than hoped.
#
# WHY NOT A POSTGRES SEQUENCE. A sequence created outside the schema does not appear in `db/schema.rb`, so a
# fresh `db:schema:load` has none and the first insert raises -- one of the four costs the tenant desk already
# enumerated when it faced this choice. Adding a mechanism whose failure mode is "a new developer's database is
# broken until somebody remembers" to save microseconds is the wrong trade.
#
# Numbers are not reused: a ticket is closed, never destroyed, and no endpoint deletes one.
module PlatformSupport::ReferenceAllocator
  # Any stable 32-bit value works; hashtext of a fixed string keeps it readable in pg_locks.
  LOCK_NAMESPACE_SQL = "hashtext('platform_support_reference')".freeze

  module_function

  # Call inside the creating transaction. Outside one the advisory lock is released immediately and the number
  # it returns is a guess.
  def next_reference_number
    connection = PlatformSupport::Ticket.connection
    connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE_SQL}, 0)")
    highest = connection.select_value(
      PlatformSupport::Ticket.unscoped.select('MAX(reference_number)').to_sql
    )
    highest.to_i + 1
  end
end
