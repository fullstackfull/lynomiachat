# Consent a customer gave to an approved external PARTNER, kept beside Lynomia's own consent
# store rather than inside it (docs/partner-consent/ADR-001-partner-scoped-consent.md).
#
# WHY A SEPARATE TABLE AND NOT A COLUMN ON commerce_messaging_consents. That table is
# UNIQUE (contact_id, purpose) -- one decision per person per class, for the whole account.
# Adding a partner to it would mean widening that key, which changes what every existing row
# means and what every existing reader gets back. The native store keeps its semantics exactly;
# this one carries the partner-scoped evidence that has nowhere to live today.
#
# THE STORE IS IN THE UNIQUE KEY ON PURPOSE. Two stores of one merchant are two scopes, and a
# grant captured at one store's checkout authorises nothing at the other. Putting
# commerce_store_id in the key makes "a partner's grant never authorises another partner's
# messages" a property the database enforces, rather than a rule a future reader has to
# remember. The same key makes a withdrawal scope-exact: it ends the grant it matches and
# leaves every other store, class and channel alone.
#
# commerce_stores IS THE INSTALLATION REGISTRY. It is already multi-provider (woocommerce,
# salla, zid, shopify, storesyria) and already carries the account binding, the lifecycle
# status and the credentials. A parallel partner_installations table would be a second place
# the same installation exists, free to disagree with the first. The limit is recorded rather
# than hidden: a future NON-commerce partner has no store row and onboarding one means giving
# it an installation row -- see ADR-001 section 6.
#
# NOTHING IS BACKFILLED. Every existing consent decision stays exactly where it is and means
# exactly what it meant. campaigns.commerce_store_id is null for every existing campaign,
# which is precisely what marks them as not partner-originated.
class CreatePartnerConsents < ActiveRecord::Migration[7.1]
  def change
    create_consents_table
    add_scope_indexes
    add_campaign_origin
  end

  def create_consents_table
    create_table :partner_consents do |t|
      # WHO ASSERTED IT. The Platform App that authenticated the write -- provenance, so a
      # grant can be traced to the credential that recorded it even after an integration ends.
      t.references :platform_app, null: false, foreign_key: true
      # THE BOUND ACCOUNT, denormalised from the store so cross-account isolation can be
      # enforced and indexed without a join on every eligibility read.
      t.references :account, null: false, foreign_key: true
      # THE INSTALLATION. Restricting to one store is what makes the grant scope-bound.
      t.references :commerce_store, null: false, foreign_key: true
      # THE VERIFIED SUBJECT. A Lynomia contact, reached through commerce_customer_links, so
      # no name, phone or email is copied here -- that mapping already exists.
      t.references :contact, null: false, foreign_key: true

      t.string :external_subject_id, limit: 128, null: false
      t.integer :purpose, null: false
      t.integer :channel, null: false
      t.integer :state, null: false
      t.string :source, limit: 40, null: false
      # The notice the customer was actually shown. Without it a grant cannot be defended
      # later, because nobody can say what was on the screen when it was given.
      t.string :policy_version, limit: 40
      t.datetime :captured_at, null: false
      t.datetime :withdrawn_at
      t.jsonb :evidence, null: false, default: {}
      t.references :recorded_by, foreign_key: { to_table: :users }

      t.timestamps
    end
  end

  def add_scope_indexes
    add_index :partner_consents, %i[commerce_store_id contact_id purpose channel],
              unique: true, name: 'index_partner_consents_on_scope'
    add_index :partner_consents, %i[account_id state], name: 'index_partner_consents_on_account_and_state'
    add_index :partner_consents, %i[platform_app_id account_id], name: 'index_partner_consents_on_app_and_account'
    add_index :partner_consents, %i[commerce_store_id external_subject_id],
              name: 'index_partner_consents_on_store_and_subject'
  end

  def add_campaign_origin
    # NULL MEANS "NOT PARTNER-ORIGINATED", which is every campaign that exists today. The
    # partner checks at the send boundary are reached only when this is set, so no historical
    # campaign changes meaning.
    add_reference :campaigns, :commerce_store, null: true, foreign_key: true, index: true
  end
end
