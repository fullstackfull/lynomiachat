# Lynomia: make the TikTok user id findable (docs/p10/02-channel-capability-matrix.md §TikTok).
#
# TikTok writes the CONVERSATION id to `contact_inboxes.source_id`
# (app/services/tiktok/message_service.rb:34 -> messaging_helpers.rb:4-9), and the customer's actual TikTok user
# id only to `contacts.additional_attributes['social_tiktok_user_id']`, which nothing ever reads back.
# `ContactInboxWithContactBuilder#find_contact` matches on identifier, email and phone, and TikTok supplies none
# of the three -- so every new TikTok conversation creates a BRAND-NEW Contact for a customer the account
# already has. One human, one channel, as many contacts as conversations.
#
# The fix is a deterministic lookup on that stored user id, and this is the index that makes it a probe rather
# than a sequential scan over `contacts`. Partial, because only TikTok contacts carry the key: on an account
# with no TikTok inbox the index holds nothing.
#
# The expression is written out in full rather than parameterised because an expression index is only used when
# the query contains the same literal expression; the matching WHERE fragment lives beside it in
# Custom::ContactInboxWithContactBuilder::SOCIAL_IDENTITY_LOOKUPS.
class AddSocialIdentityIndexToContacts < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL.squish
      CREATE INDEX index_contacts_on_social_tiktok_user_id
      ON contacts (account_id, (additional_attributes ->> 'social_tiktok_user_id'))
      WHERE additional_attributes ? 'social_tiktok_user_id'
    SQL
  end

  def down
    execute 'DROP INDEX IF EXISTS index_contacts_on_social_tiktok_user_id'
  end
end
