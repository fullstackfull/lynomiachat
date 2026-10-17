# One Stripe money object and the Odoo accounting document it became (docs/odoo/02-architecture.md §5).
#
# THE IDEMPOTENCY RECORD. `idempotency_key` is the brief's key, built and stored verbatim:
#
#   LYNOMIA_CHAT:live:stripe:customer_invoice:in_1A2b3C:profile_7
#
# source app, environment, provider, document kind, the provider's own object id, and the destination profile.
# Its unique index is the ONLY thing that decides whether a document has already been exported -- not a plan
# name, not a customer email, not an invoice number, each of which can legitimately repeat across the
# businesses sharing this Odoo database.
#
# The document kind is part of the key because one Stripe invoice produces more than one accounting document
# over its life: the customer invoice, then the payment, then possibly a credit note. They are separate rows
# with separate keys, so registering a payment can never be mistaken for re-creating the invoice.
class CreateOdooDocumentMappings < ActiveRecord::Migration[7.2]
  def change
    create_table :odoo_document_mappings do |t|
      t.references :odoo_destination_profile, null: false, foreign_key: true, index: false
      t.references :odoo_customer_mapping, foreign_key: true

      # Scoping for the operator screens, which list by account. Nullable: a document whose customer could not
      # be resolved still needs a row, because that is the state a human has to act on.
      t.integer :account_id

      # The Stripe side. `provider` is a column rather than an assumption so a second payment provider would
      # not need a second table -- Stripe is the only authority today and the only value written.
      t.string :provider, null: false, default: 'stripe'
      t.string :provider_object_type, null: false
      t.string :provider_object_id, null: false
      # The object's own date at Stripe, not when we processed it: an accounting document belongs to the period
      # the money moved in, which is not the period our worker happened to run in.
      t.datetime :occurred_at

      # What we are making in Odoo. `odoo_record_id` is null until the write succeeds, and
      # `odoo_document_reference` stays null until POSTING assigns a name -- a draft invoice has no number,
      # and inventing one would be inventing accounting.
      t.string :document_kind, null: false
      t.string :odoo_model
      t.integer :odoo_record_id
      t.string :odoo_document_reference

      # What Odoo last TOLD us, read back rather than assumed. `odoo_payment_state` is Odoo's own computed
      # field: it is recorded here for display and never written to Odoo, because forcing a computed payment
      # status is how a ledger starts lying about whether it was paid.
      t.string :odoo_state
      t.string :odoo_payment_state
      t.datetime :odoo_state_read_at

      # The amount as Stripe reported it, in the provider's own minor units, with its own currency. Not
      # recomputed from a BillingPlan price: what a customer was actually charged is the invoice, and a plan's
      # list price is not evidence of it.
      t.bigint :amount_minor
      t.string :currency

      t.string :source_reference, null: false
      t.string :idempotency_key, null: false

      # pending / processing / synchronized / retrying / failed / blocked / needs_review.
      t.integer :state, null: false, default: 0
      t.string :needs_review_reason
      t.string :last_error_class
      t.datetime :posted_at
      t.datetime :last_synced_at

      t.timestamps
    end

    # The guarantee. One row per key, decided by PostgreSQL rather than by a read-then-write race.
    add_index :odoo_document_mappings, :idempotency_key, unique: true, name: 'uniq_odoo_document_mapping_idempotency_key'

    # Recovery after a lost answer: given a Stripe object, find whatever we already recorded about it at this
    # destination, whichever kind of document it became.
    add_index :odoo_document_mappings, [:odoo_destination_profile_id, :provider, :provider_object_id],
              name: 'index_odoo_document_mappings_on_provider_object'
    # The Invoices and Transactions screens.
    add_index :odoo_document_mappings, [:state, :occurred_at], name: 'index_odoo_document_mappings_on_state'
    add_index :odoo_document_mappings, [:account_id, :occurred_at], name: 'index_odoo_document_mappings_on_account'
    add_index :odoo_document_mappings, :source_reference
  end
end
