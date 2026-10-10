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
class AddSocialIdentityIndexToContacts < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL.squish
      CREATE INDEX index_contacts_on_social_tiktok_user_id
      ON contacts ((additional_attributes ->> 'social_tiktok_user_id'), account_id)
    SQL
  end

  def down
    execute 'DROP INDEX IF EXISTS index_contacts_on_social_tiktok_user_id'
  end
end
