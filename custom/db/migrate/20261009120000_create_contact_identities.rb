# Lynomia unified identity: the additional phone numbers and email addresses a Contact owns but cannot store
# (docs/p10/03-unified-customer-identity.md).
#
# WHY THE EXISTING MODEL FAILS. `contacts` carries three FULL unique indexes per account --
# `uniq_email_per_account_contact`, `uniq_phone_number_per_account_contact`, `uniq_identifier_per_account_contact`
# -- and `Contact#prepare_contact_attributes` turns a blank into NULL so the uniqueness is real rather than
# defeated by empty strings. One Contact is therefore exactly one phone number, one email address and one
# identifier. A customer who writes from a second WhatsApp number is a second Contact, and the merge that an
# agent performs to join them keeps only one of each: `ContactMergeAction#merge_and_remove_mergee_contact`
# compact_blanks both sides and gives the base preference, so the mergee's number is destroyed with its row.
# Measured on a real account (docs/p10/03-unified-customer-identity.md §2): after the merge the second number
# exists nowhere, and the next inbound message carrying it through an inbox the merge did not touch creates a
# brand-new Contact. The merge does not stick, and the agent does it again.
#
# WHY A JSONB ATTRIBUTE IS NOT ENOUGH. `additional_attributes` and `custom_attributes` are written by the
# ordinary contact-update endpoint, by `Contacts::SyncAttributes` and by the CSV importer, so an identity claim
# there is client-supplied data. Nothing can make it unique, so two contacts could both claim one number and the
# inbound match becomes a guess -- the one thing P10 must never do. And resolving "who owns +965..." would mean
# a jsonb containment scan on the hot inbound path.
#
# WHY CONTACT_INBOX IS NOT ENOUGH. `ContactInbox` already holds many provider identities per contact, one per
# inbox, and that part of omnichannel identity works today. But it validates `inbox_id` presence
# (app/models/contact_inbox.rb:26) and its `source_id` is a provider-scoped string, unique only per inbox. "This
# person also owns this number" is an account-level fact about a human, not a membership of a channel; recording
# it as one would mean inventing an inbox, would inherit pubsub-token and conversation-routing side effects, and
# still could not stop two contacts in the account claiming the same number.
#
# WHY A LINK TABLE IS REQUIRED. The account-scoped UNIQUE below is the whole point: one normalized identity value
# belongs to at most one contact in an account, which is what makes the inbound match deterministic instead of
# probabilistic. It is the same guarantee `contacts` gives for the primary fields, extended to the values
# `contacts` has no column for.
#
# WHAT THIS TABLE DELIBERATELY IS NOT. It does not mirror `contacts.phone_number` or `contacts.email`; those
# stay the primary fields and keep their own unique indexes. This table holds only the additional values, so an
# empty table means the product behaves exactly as it does today and no backfill is needed to deploy it.
# `source` has two values and neither is a similarity score: an identity is recorded because an agent said so,
# or because a merge absorbed a value that was already a verified primary field. There is no fuzzy source
# because there is no fuzzy matching.
#
# ROLLBACK. `drop_table` is the whole of it. The table is additive, nothing in `contacts`, `contact_inboxes`,
# `conversations` or `messages` references it, and the paths that read it fall back to today's behaviour when it
# is absent -- so a rollback loses the recorded links and nothing else.
class CreateContactIdentities < ActiveRecord::Migration[7.2]
  def change
    create_table :contact_identities do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :contact, null: false, index: false, foreign_key: { on_delete: :cascade }
      # 0 phone, 1 email. Normalized before it is stored: phone through Contacts::Phone.e164, the one E.164 path
      # in the app, and email downcased -- the same normalization `contacts` applies to its own columns.
      t.integer :identity_type, null: false
      t.string :value, null: false
      # 0 agent_linked, 1 merged.
      t.integer :source, null: false, default: 0
      t.references :linked_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    # The deterministic guarantee AND the inbound lookup, which is an equality match on all three columns:
    # `account_id = ? AND identity_type = ? AND value = ?`.
    add_index :contact_identities, [:account_id, :identity_type, :value], unique: true,
                                                                          name: 'index_contact_identities_on_account_type_value'
    # The contact's own panel, and the move a merge performs.
    add_index :contact_identities, :contact_id
  end
end
