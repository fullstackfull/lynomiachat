# Whether `contacts.phone_number` can be made unique per account, and what is in the way.
#
# `(email, account_id)` and `(identifier, account_id)` are UNIQUE in the database; `(phone_number, account_id)`
# is only an ordinary index, so the model's `uniqueness` validation is all that stands between two concurrent
# writes and two contacts sharing a number (docs/contacts/11-phone-uniqueness.md).
#
# Two things can be in the way, and they are different problems:
#
#   * **Blank strings.** `Contact#prepare_email_attribute` turns a blank email into NULL precisely so the unique
#     index tolerates "no email"; nothing does that for `phone_number`. NULLs are distinct from each other in
#     PostgreSQL, so any number of contacts may have no number — but `''` is a value, and two of those collide.
#   * **Real duplicates.** Two contacts in one account with the same number. The validation lets these through
#     under concurrency, and `DataImport` used to insert them from one file.
#
# Both tasks only read. Neither takes a lock.
#
# Usage:
#   bundle exec rake contacts:phone_uniqueness:audit             # what is there
#   bundle exec rake contacts:phone_uniqueness:dry_run           # what the migration would do, and whether it can
#   ACCOUNT_ID=1 bundle exec rake contacts:phone_uniqueness:audit
#
# A full-table GROUP BY on contacts can outrun `statement_timeout`, which `config/database.yml` sets to 14s for
# every connection. Both tasks clear it for their own session only.
#
# rubocop:disable Metrics/BlockLength
namespace :contacts do
  namespace :phone_uniqueness do
    def with_unlimited_statement_timeout
      ActiveRecord::Base.connection.execute("SET statement_timeout = '0'")
      yield
    ensure
      ActiveRecord::Base.connection.execute('RESET statement_timeout')
    end

    def account_scope
      account_id = ENV.fetch('ACCOUNT_ID', nil)
      return 'TRUE' if account_id.blank?

      ActiveRecord::Base.sanitize_sql_array(['account_id = ?', account_id.to_i])
    end

    def duplicate_groups
      ActiveRecord::Base.connection.exec_query(<<~SQL.squish)
        SELECT account_id, phone_number, COUNT(*) AS rows, MIN(id) AS keep_id, ARRAY_AGG(id ORDER BY id) AS ids
        FROM contacts
        WHERE phone_number IS NOT NULL AND phone_number <> '' AND #{account_scope}
        GROUP BY account_id, phone_number
        HAVING COUNT(*) > 1
        ORDER BY COUNT(*) DESC, account_id
      SQL
    end

    def blank_counts
      ActiveRecord::Base.connection.exec_query(<<~SQL.squish)
        SELECT
          COUNT(*) FILTER (WHERE phone_number = '') AS blank_phone,
          COUNT(*) FILTER (WHERE phone_number IS NULL) AS null_phone,
          COUNT(*) FILTER (WHERE identifier = '') AS blank_identifier,
          COUNT(*) AS total
        FROM contacts
        WHERE #{account_scope}
      SQL
    end

    def blank_phone_collisions
      ActiveRecord::Base.connection.exec_query(<<~SQL.squish)
        SELECT account_id, COUNT(*) AS rows
        FROM contacts
        WHERE phone_number = '' AND #{account_scope}
        GROUP BY account_id
        HAVING COUNT(*) > 1
        ORDER BY COUNT(*) DESC
      SQL
    end

    desc 'Report what stands between contacts.phone_number and a unique index (read-only)'
    task audit: :environment do
      with_unlimited_statement_timeout do
        counts = blank_counts.first
        puts "Contacts examined: #{counts['total']}"
        puts "  phone_number IS NULL: #{counts['null_phone']}  (any number of these is fine — NULLs are distinct)"
        puts "  phone_number = '':    #{counts['blank_phone']}  (two of these in one account collide)"
        puts "  identifier = '':      #{counts['blank_identifier']}  (the identifier index is already UNIQUE)"

        collisions = blank_phone_collisions
        puts "\nAccounts with more than one blank-string phone number: #{collisions.count}"
        collisions.each { |row| puts "  account #{row['account_id']}: #{row['rows']} rows" }

        duplicates = duplicate_groups
        puts "\nDuplicate (account_id, phone_number) groups: #{duplicates.count}"
        puts "Contacts involved: #{duplicates.sum { |row| row['rows'] }}"
        duplicates.first(50).each do |row|
          puts "  account #{row['account_id']} #{row['phone_number']}: #{row['rows']} rows #{row['ids']}"
        end
        puts '  ...' if duplicates.count > 50
      end
    end

    desc 'What the unique-index migration would do, and whether it would succeed (read-only)'
    task dry_run: :environment do
      with_unlimited_statement_timeout do
        blanks = blank_counts.first['blank_phone'].to_i
        duplicates = duplicate_groups

        puts "Step 1 — UPDATE contacts SET phone_number = NULL WHERE phone_number = '': #{blanks} row(s)"
        puts 'Step 2 — CREATE UNIQUE INDEX CONCURRENTLY uniq_phone_number_per_account_contact ON contacts (phone_number, account_id)'
        puts 'Step 3 — DROP INDEX index_contacts_on_phone_number_and_account_id (the new one subsumes it)'

        if duplicates.any?
          puts "\nWould FAIL. #{duplicates.count} duplicate group(s), #{duplicates.sum { |row| row['rows'] }} contacts."
          puts 'Resolve them first; the migration refuses rather than leaving an INVALID index behind.'
          duplicates.first(50).each do |row|
            puts "  account #{row['account_id']} #{row['phone_number']}: keep #{row['keep_id']}, conflicts #{row['ids']}"
          end
          puts '  ...' if duplicates.count > 50
        else
          puts "\nWould succeed. No duplicate (account_id, phone_number) pairs."
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
