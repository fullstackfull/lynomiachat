# One table for the explicit, audited commercial exceptions an operator grants to a single account
# (docs/p11/03-plans-entitlements.md).
#
# WHY THE EXISTING MODEL FAILS
#   Plan features are applied by writing them into the account's own feature-flag bitmask
#   (Billing::FeatureSync), and that write is unconditional in both directions: `disable_features(*(managed -
#   included))`. So an operator who switches a managed feature on for one account loses it at the next plan
#   sync, and nothing anywhere records that the decision was deliberate. The same storage cannot hold both
#   "the plan includes this" and "a human decided this for this account", which is the distinction P11.4 is
#   about and the reason a capability's source cannot be answered today.
#
# WHY A JSONB COLUMN IS NOT ENOUGH
#   An override has to carry who granted it, when, why, and optionally when it lapses, and it has to be
#   queryable per capability so the entitlement service can resolve one without loading them all. A jsonb bag
#   on `accounts` or `billing_subscriptions` would be untyped, unconstrained and unindexable per capability,
#   and the project's own rule is not to reach for untyped JSON when a structured model fits.
#   `accounts.limits` is not a candidate either: it exists but is Chatwoot Cloud's own
#   {conversation:, non_web_inboxes:, agents:} shape with allowed/consumed pairs, still read by
#   UpgradePage.vue, and nothing server-side consults it.
#
# WHY NOT ON billing_subscriptions
#   An override outlives a subscription. A complimentary account may have no Stripe subscription at all, and a
#   plan change must not silently drop an exception an operator granted. It belongs to the account.
#
# UNIQUENESS
#   One override per (account, kind, name). Granting the same capability twice is an edit, not a second row.
#
# QUERY SHAPES
#   1. resolve one capability for one account   -> (account_id, kind, name), the unique index
#   2. list an account's overrides for the console -> (account_id, kind, name) prefix
#   3. expire what has lapsed                   -> expires_at, partial on the rows that have one
#
# ROLLBACK
#   drop_table. Nothing references it, and Billing::Entitlements falls back to exactly today's behaviour when
#   the table is empty, so an empty table is a no-op and no backfill exists or is needed.
class CreateBillingEntitlementOverrides < ActiveRecord::Migration[7.1]
  def change
    create_table :billing_entitlement_overrides do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.integer :kind, null: false
      t.string :name, null: false
      t.boolean :enabled
      t.integer :limit_value
      t.string :reason, null: false
      t.references :granted_by, null: true, foreign_key: { to_table: :users }
      t.datetime :expires_at
      t.timestamps
    end

    add_index :billing_entitlement_overrides, [:account_id, :kind, :name],
              unique: true, name: 'uniq_billing_override_per_account_capability'
    add_index :billing_entitlement_overrides, :expires_at,
              where: 'expires_at IS NOT NULL', name: 'index_billing_overrides_on_expiry'
  end
end
