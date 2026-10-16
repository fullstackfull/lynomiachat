# One configured Odoo destination: where Lynomia Chat's own accounting documents are written, and under whose
# company, journal and analytic account (docs/odoo/02-architecture.md §2).
#
# A PROFILE, NOT INSTALLATION CONFIGS. Billing::Settings keeps the Stripe keys as locked installation_configs
# rows, and that is right for one global switch per key. This is not that: the destination carries a company, a
# journal, an analytic account, a detected server version, an activation state and the proof that a write
# actually worked -- state that belongs to one destination and would be a dozen unrelated global keys. More
# importantly `installation_configs.value` is NOT encrypted at rest, only `locked`, and the brief requires the
# Odoo credential to be encrypted. So this follows commerce_stores: a JSON `credentials` column the model
# declares `encrypts` on, refusing to persist without Active Record encryption keys.
#
# Additive and `change`-based: it inverts mechanically and nothing existing reads or writes it.
class CreateOdooDestinationProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :odoo_destination_profiles do |t|
      # What an operator calls this destination. Unique so two rows cannot be told apart only by id in a flash
      # message or an audit entry.
      t.string :name, null: false

      # The two halves of the isolation stamp, stored on the destination rather than per document because they
      # are properties of the destination and a document cannot belong to two. Every exported record carries
      # them, which is how a search can never match another project's rows.
      t.string :source_app, null: false, default: 'LYNOMIA_CHAT'
      t.string :environment, null: false

      # Connection. `base_url` is https-only and SSRF-checked at the boundary; `database` and `username` are not
      # secrets but are still never rendered into a public response.
      t.string :base_url, null: false
      t.string :database, null: false
      t.string :username, null: false
      # Encrypted JSON: { "api_key" => ... }. Text, because an encrypted payload is longer than its plaintext.
      t.text :credentials

      # What the server told us about itself, read BEFORE authenticating. `transport` is derived from it, so a
      # profile configured against Odoo 19 and one against Odoo 17 speak different dialects without the caller
      # knowing. Both nullable: a profile exists before it has ever been reached.
      t.string :odoo_version
      t.jsonb :odoo_version_info, null: false, default: {}
      t.string :transport

      # The destination scope. An export names ALL of these, and a lookup is scoped by them, which is what
      # stops this integration seeing or touching another business's books in the same database. The `*_name`
      # columns are the labels captured when the operator chose, so a screen can say what was chosen without a
      # round trip -- and so an audit entry still reads sensibly after the label changes in Odoo.
      t.integer :company_id
      t.string :company_name
      t.integer :journal_id
      t.string :journal_name
      t.integer :payment_journal_id
      t.string :payment_journal_name
      t.integer :analytic_account_id
      t.string :analytic_account_name
      t.integer :default_product_id
      t.string :default_product_name

      # Activation. Three separate switches, because the brief requires posting and payment registration to be
      # configurable INDEPENDENTLY of synchronisation and to stay off until each has been validated against the
      # real server. All three default to false: a freshly configured profile writes nothing.
      t.boolean :sync_enabled, null: false, default: false
      t.boolean :post_invoices, null: false, default: false
      t.boolean :register_payments, null: false, default: false

      # What we have actually proven, as opposed to what we have configured. A successful login proves only
      # that a login works; `last_capability_proof_at` is stamped when a real draft invoice was created and
      # rolled back, which is the only evidence that posting will work.
      t.datetime :last_connection_test_at
      t.jsonb :last_connection_result, null: false, default: {}
      t.datetime :last_capability_proof_at
      t.jsonb :last_capability_proof, null: false, default: {}

      # Why this profile is refusing to run, when it is. A classification, never a provider message.
      t.string :blocked_reason

      t.timestamps
    end

    add_index :odoo_destination_profiles, :name, unique: true

    # THE EXCLUSIVITY GUARANTEE, in the database rather than in a callback. Two profiles may exist for the same
    # app and environment -- an operator reconfiguring a destination needs that -- but only ONE may be enabled,
    # because two enabled profiles would post every invoice twice. PostgreSQL allows unlimited rows that fail
    # the predicate, so disabled profiles are unaffected.
    add_index :odoo_destination_profiles, [:source_app, :environment],
              unique: true, where: 'sync_enabled', name: 'uniq_enabled_odoo_destination_per_environment'
  end
end
