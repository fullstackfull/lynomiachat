# Lynomia: make the TikTok user id findable (docs/p10/02-channel-capability-matrix.md §TikTok).
#
# TikTok writes the CONVERSATION id to `contact_inboxes.source_id`
# (app/services/tiktok/message_service.rb:34 -> messaging_helpers.rb:4-9), and the customer's actual TikTok user
# id only to `contacts.additional_attributes['social_tiktok_user_id']`, which nothing ever reads back.
# `ContactInboxWithContactBuilder#find_contact` matches on identifier, email and phone, and TikTok supplies none
# of the three -- so every new TikTok conversation created a BRAND-NEW Contact for a customer the account
# already had. One human, one channel, as many contacts as conversations.
#
# The fix is a deterministic lookup on that stored user id, and this is the index that makes it a probe rather
# than a parallel scan over `contacts`.
#
# TWO THINGS ABOUT ITS SHAPE WERE MEASURED, NOT ASSUMED (docs/p10/07-security-performance.md §3.3). On one
# account holding 200,000 contacts, 40,000 of them carrying the key:
#
#   (account_id, expr) WHERE additional_attributes ? 'social_tiktok_user_id'   UNUSED   21-26 ms
#   (expr, account_id) WHERE additional_attributes ? 'social_tiktok_user_id'   UNUSED   20-22 ms
#   (expr, account_id)                                                         USED      0.045 ms
#
# The expression has to LEAD, because `account_id` is not selective inside the account doing the asking. And the
# index cannot be PARTIAL: PostgreSQL will only use a partial index when it can prove the query implies the
# predicate, and `(additional_attributes ->> 'k') = 'v'` does not prove `additional_attributes ? 'k'` -- the two
# operators are unrelated as far as the prover is concerned. Adding the containment test to the query did not
# help either (both partial variants above were measured with and without it). So the index covers every
# contact; at this scale that is 4,712 kB against a 61 MB table.
#
# P-FINAL (docs/p-final/03-migration-review.md §3): built CONCURRENTLY. This is the only migration in the
# release that indexes a table production already holds rows in, and a plain CREATE INDEX holds ACCESS
# EXCLUSIVE on `contacts` for the whole build -- so every inbound message that creates or touches a contact
# waits behind it, on the busiest table in the product, during a deploy. The same three precautions the
# repository's own concurrent-index migrations take are taken here, for the same measured reasons:
#   * `disable_ddl_transaction!`, because CONCURRENTLY cannot run inside a transaction;
#   * `SET statement_timeout = '0'`, because config/database.yml:13 sets 14s on every connection including
#     production's, and being killed by that timeout is exactly what leaves an index INVALID;
#   * an explicit INVALID-leftover check, because `IF NOT EXISTS` would skip the rebuild and report success
#     while the index served nothing -- and deployment/deploy.sh:176-183 aborts the deploy on an invalid index,
#     so a skipped rebuild would be a loop the operator cannot leave by re-running.
# Precedent in this tree: custom/db/migrate/20261004110000_add_unique_phone_number_index_to_contacts.rb, plus
# 21 upstream migrations, two of them on `contacts`
# (db/migrate/20230727065605_add_partial_index_contact_account_id.rb,
# db/migrate/20250722152516_add_index_on_contact_type_and_account_id_to_contacts.rb).
#
# db/schema.rb is unchanged by this: the index definition is identical, only the way it is built differs.
class AddSocialIdentityIndexToContacts < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDEX_NAME = 'index_contacts_on_social_tiktok_user_id'.freeze

  def up
    unlimit_statement_timeout
    drop_invalid_index
    return say("#{INDEX_NAME} already exists and is valid") if index_state == :valid

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY #{INDEX_NAME}
      ON contacts ((additional_attributes ->> 'social_tiktok_user_id'), account_id)
    SQL
  end

  def down
    unlimit_statement_timeout
    execute "DROP INDEX CONCURRENTLY IF EXISTS #{INDEX_NAME}"
  end

  private

  def unlimit_statement_timeout
    execute("SET statement_timeout = '0'")
  end

  # An interrupted CREATE INDEX CONCURRENTLY -- the statement timeout, a cancelled migration, a killed deploy --
  # leaves the index present and marked INVALID: answering no query, and in the way of the retry.
  def drop_invalid_index
    return unless index_state == :invalid

    say "#{INDEX_NAME} exists but is INVALID, left by an interrupted build; dropping it and rebuilding"
    execute "DROP INDEX CONCURRENTLY IF EXISTS #{INDEX_NAME}"
  end

  def index_state
    valid = select_value(<<~SQL.squish)
      SELECT i.indisvalid FROM pg_class c
      JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = #{quote(INDEX_NAME)}
    SQL
    return :absent if valid.nil?

    ActiveRecord::Type::Boolean.new.cast(valid) ? :valid : :invalid
  end
end
