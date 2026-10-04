# `(email, account_id)` and `(identifier, account_id)` have been UNIQUE in `contacts` since Chatwoot's first
# schema. `(phone_number, account_id)` has only ever been an ordinary index, so the model's `uniqueness`
# validation was the whole of the rule — and a validation cannot see a row that does not exist yet. Two
# simultaneous creates, or one CSV import, produced two contacts sharing a number
# (docs/contacts/11-phone-uniqueness.md).
#
# Run `bundle exec rake contacts:phone_uniqueness:dry_run` before this. It reports, without taking a lock,
# exactly what this does and whether it can.
class AddUniquePhoneNumberIndexToContacts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  UNIQUE_INDEX = 'uniq_phone_number_per_account_contact'.freeze
  PLAIN_INDEX = 'index_contacts_on_phone_number_and_account_id'.freeze
  BATCH_SIZE = 1000

  def up
    unlimit_statement_timeout
    drop_invalid_unique_index
    normalize_blank_phone_numbers
    refuse_on_duplicates

    add_index :contacts, [:phone_number, :account_id], unique: true, name: UNIQUE_INDEX, algorithm: :concurrently
    # Exactly the same columns in exactly the same order, so the unique one subsumes it.
    remove_index :contacts, name: PLAIN_INDEX, algorithm: :concurrently, if_exists: true
  end

  def down
    unlimit_statement_timeout
    # The replacement first, so `phone_number` is never left unindexed — `ContactInboxWithContactBuilder`
    # looks a contact up by number on every inbound message.
    add_index :contacts, [:phone_number, :account_id], name: PLAIN_INDEX, algorithm: :concurrently, if_not_exists: true
    remove_index :contacts, name: UNIQUE_INDEX, algorithm: :concurrently, if_exists: true
    # The blank-to-NULL normalization is not undone. `''` and NULL both mean "no number", and NULL is the one
    # every other identity column on this table already uses for it.
  end

  private

  # `config/database.yml` sets `statement_timeout: 14s` on every connection, production included. A concurrent
  # index build on a large `contacts` takes longer than that, and being killed by the timeout is precisely what
  # leaves an INVALID index behind.
  def unlimit_statement_timeout
    execute("SET statement_timeout = '0'")
  end

  # An interrupted `CREATE INDEX CONCURRENTLY` — the timeout above, a cancelled migration, a deploy — leaves the
  # index present and marked INVALID: enforcing nothing, and in the way of the retry. `if_not_exists: true` is
  # the wrong answer, because it would skip the build and report success while the column stayed unconstrained.
  def drop_invalid_unique_index
    invalid = select_value(<<~SQL.squish)
      SELECT c.relname FROM pg_class c
      JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = #{quote(UNIQUE_INDEX)} AND NOT i.indisvalid
    SQL
    return if invalid.blank?

    say "#{UNIQUE_INDEX} exists but is INVALID, left by an interrupted build; dropping it and rebuilding"
    remove_index :contacts, name: UNIQUE_INDEX, algorithm: :concurrently
  end

  # NULLs are distinct from one another in PostgreSQL, so any number of contacts may have no phone number — but
  # `''` is a value, and the second one collides. `Contact#prepare_email_attribute` has always done this for
  # email, with that comment; nothing did it for `phone_number`, and `PATCH /contacts/:id` with
  # `phone_number: ""` writes one.
  def normalize_blank_phone_numbers
    loop do
      updated = execute(<<~SQL.squish).cmd_tuples
        UPDATE contacts SET phone_number = NULL
        WHERE id IN (SELECT id FROM contacts WHERE phone_number = '' LIMIT #{BATCH_SIZE})
      SQL
      say "normalized #{updated} blank phone number(s) to NULL" if updated.positive?
      break if updated < BATCH_SIZE
    end
  end

  # Refused before the build, not during it: a failed `CREATE UNIQUE INDEX CONCURRENTLY` leaves an INVALID index
  # behind, so finding out from the build is the expensive way to find out.
  def refuse_on_duplicates
    duplicates = select_all(<<~SQL.squish).to_a
      SELECT account_id, phone_number, COUNT(*) AS rows
      FROM contacts
      WHERE phone_number IS NOT NULL
      GROUP BY account_id, phone_number
      HAVING COUNT(*) > 1
      ORDER BY COUNT(*) DESC
      LIMIT 20
    SQL
    return if duplicates.empty?

    listed = duplicates.map { |row| "account #{row['account_id']} #{row['phone_number']} (#{row['rows']} rows)" }
    raise 'contacts holds duplicate (account_id, phone_number) rows, so the unique index cannot be created. ' \
          'Run `bundle exec rake contacts:phone_uniqueness:audit` for the full list and resolve them first. ' \
          "First #{duplicates.size}: #{listed.join('; ')}"
  end
end
