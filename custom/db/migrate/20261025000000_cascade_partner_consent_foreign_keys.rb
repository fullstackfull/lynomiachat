# WHAT HAPPENS TO A CONSENT RECORD WHEN THE THING IT IS ABOUT GOES AWAY.
#
# `partner_consents` and `partner_consent_events` were created with plain `foreign_key: true`,
# which in Postgres is ON DELETE NO ACTION -- the delete is REFUSED. Every other
# contact-owned table in this overlay says what should happen instead: `campaign_recipients`,
# `commerce_customer_links` and `contact_identities` all cascade from the contact, the store
# and the account, and nullify the user who acted. These two said nothing, so:
#
#   * deleting a contact who had ever opted in at a partner checkout raised
#     ActiveRecord::InvalidForeignKey. A merchant could not delete their own customer, and
#     neither could an erasure request -- and the people it blocked were exactly the people
#     the integration had collected consent from.
#   * releasing a store another account had disconnected raised the same, because
#     Commerce::StoreConnection#claim destroys the released row before taking it.
#   * deleting an account raised it too.
#
# CASCADE, NOT NULLIFY, AND NOT RESTRICT. A consent decision is a fact ABOUT A PERSON at an
# installation. With the person erased there is nobody to message, and keeping the decision
# would be keeping personal data past the erasure that was supposed to remove it. The
# evidence is not lost in the ordinary case either: `Custom::AuditLog` records the decision
# as it happens and is not a child of the contact.
#
# THE OPERATOR IS THE EXCEPTION. `recorded_by_id` names whoever typed the decision, which is
# not what the decision is about, so deleting them leaves the record and forgets the typist
# -- the rule `commerce_customer_links.confirmed_by_id` already follows.
class CascadePartnerConsentForeignKeys < ActiveRecord::Migration[7.2]
  TABLES = %i[partner_consents partner_consent_events].freeze
  CASCADE = { contacts: nil, commerce_stores: nil, accounts: nil, platform_apps: nil }.freeze

  def up
    TABLES.each do |table|
      CASCADE.each_key do |parent|
        remove_foreign_key table, parent
        add_foreign_key table, parent, on_delete: :cascade
      end

      remove_foreign_key table, column: :recorded_by_id
      add_foreign_key table, :users, column: :recorded_by_id, on_delete: :nullify
    end
  end

  def down
    TABLES.each do |table|
      CASCADE.each_key do |parent|
        remove_foreign_key table, parent
        add_foreign_key table, parent
      end

      remove_foreign_key table, column: :recorded_by_id
      add_foreign_key table, :users, column: :recorded_by_id
    end
  end
end
