# Seats (and other ceilings) an INTEGRATION includes with its own product.
#
# WHY NOT A BillingEntitlementOverride, which already exists and already means "somebody granted
# this account N agents". Because an override is documented as "an operator's explicit, audited,
# reasoned decision for this one account", and it WINS over the plan for exactly that reason. A
# machine-maintained allowance that follows an external plan is a different thing: it changes
# whenever the merchant changes their Store Syria package, and writing it into the override row
# would mean an automated sync silently overwriting an operator's deliberate decision. That is
# precisely the hazard Billing::FeatureSync is documented as avoiding for features, and the same
# argument applies to limits.
#
# So this is a separate, lower-precedence layer with its own provenance, and
# Billing::Entitlements composes the two rather than one replacing the other.
#
# COMPOSED BY MAX, NOT BY SUM. A merchant with an independent Lynomia plan for 10 agents who also
# gets 5 included through an integration has 10 -- not 15, which would be additive stacking of
# overlapping quotas, and not 5, which would downgrade rights they paid for separately. nil on
# either side still means unlimited.
#
# INERT WITH NO ROWS, which is every account today.
class CreatePlatformAppEntitlementGrants < ActiveRecord::Migration[7.2]
  def change
    create_table :platform_app_entitlement_grants do |t|
      t.bigint :platform_app_id, null: false
      t.bigint :account_id, null: false

      # One of BillingPlan::LIMIT_KEYS. Named rather than agents-only because the mechanism is
      # not seat-specific and a second resource should not need a second table.
      t.string :resource, null: false, limit: 32

      # nil is NOT "unlimited" here -- a grant with no number is meaningless, so the column is
      # NOT NULL. An integration that wants to stop granting releases the row instead.
      t.integer :limit_value, null: false

      # What the integration calls the holder on its own side -- a Store Syria plan or store.
      # Carried for the audit trail and never interpreted here.
      t.string :external_ref, limit: 128

      t.timestamps
    end

    # One grant per resource per account per integration. The upsert relies on this.
    add_index :platform_app_entitlement_grants, [:platform_app_id, :account_id, :resource],
              unique: true, name: 'index_platform_app_grants_unique'
    add_index :platform_app_entitlement_grants, [:account_id, :resource]
  end
end
