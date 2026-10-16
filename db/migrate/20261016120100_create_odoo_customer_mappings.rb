# Which Odoo partner is which Lynomia account, per destination (docs/odoo/02-architecture.md §4).
#
# The chain this row closes is: Lynomia Account -> BillingSubscription -> Stripe customer -> Odoo res.partner.
# It exists because NONE of those links is derivable from a name or an email. Two unrelated Lynomia accounts
# can legitimately share a billing email, and the owner's Odoo holds partners belonging to several other
# businesses, so matching on email or name would merge books that must stay apart. The three unique indexes
# below make that merge impossible rather than merely unlikely.
class CreateOdooCustomerMappings < ActiveRecord::Migration[7.2]
  def change
    create_table :odoo_customer_mappings do |t|
      t.references :odoo_destination_profile, null: false, foreign_key: true, index: false

      # The Lynomia tenant. A plain integer reference, like billing_subscriptions.account_id, because accounts
      # are the OSS table and this is a Lynomia overlay; the index below is what reads rely on.
      t.integer :account_id, null: false

      # The Stripe customer this account pays as, copied from billing_subscriptions at mapping time. Stored
      # rather than joined, because a mapping must stay meaningful after the subscription row changes or the
      # account stops paying -- an exported partner does not become unexported.
      t.string :stripe_customer_id

      # The Odoo side. Null until the partner has been created or found: a mapping is a record of intent first
      # and of outcome second, which is what lets a conflict be reviewed instead of guessed at.
      t.integer :odoo_partner_id

      # The stamp written into Odoo's own ref field, and the only string a lookup searches on. Scoped, so it
      # cannot collide with another project's reference in the same database.
      t.string :source_reference, null: false

      # pending / synchronized / needs_review / blocked / failed. An integer enum like
      # billing_webhook_events.status, so the value is stable if a name is reworded.
      t.integer :state, null: false, default: 0
      # How the partner was decided: found by our own reference, created by us, or chosen by an operator
      # resolving a conflict. A reader must be able to tell "we made this" from "we adopted this".
      t.string :matched_by
      # Why a human is needed. A classification, never provider prose.
      t.string :review_reason

      t.datetime :last_synced_at
      t.string :last_error_class

      t.timestamps
    end

    # ONE partner per account per destination. Without this a retry that lost its answer could create a second
    # partner for the same tenant and split its ledger in two.
    add_index :odoo_customer_mappings, [:odoo_destination_profile_id, :account_id],
              unique: true, name: 'uniq_odoo_customer_mapping_per_account'

    # ONE account per partner per destination -- the other direction, and the one that actually stops a merge.
    # If two Lynomia accounts ever resolved to the same res.partner, the second insert fails and the mapping is
    # put to an operator instead of quietly billing two customers onto one partner.
    add_index :odoo_customer_mappings, [:odoo_destination_profile_id, :odoo_partner_id],
              unique: true, where: 'odoo_partner_id IS NOT NULL', name: 'uniq_odoo_customer_mapping_per_partner'

    # ONE account per Stripe customer per destination. Stripe's own customer ids are unique, so a second row
    # claiming the same one means our side disagrees with Stripe about who is paying.
    add_index :odoo_customer_mappings, [:odoo_destination_profile_id, :stripe_customer_id],
              unique: true, where: 'stripe_customer_id IS NOT NULL', name: 'uniq_odoo_customer_mapping_per_stripe_customer'

    add_index :odoo_customer_mappings, :source_reference
    # The Customers screen: everything needing a human, worst first.
    add_index :odoo_customer_mappings, [:state, :updated_at], name: 'index_odoo_customer_mappings_on_state'
  end
end
