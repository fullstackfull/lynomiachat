# Lynomia's own response targets, as data rather than as code
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M2).
#
# NO THRESHOLD VALUES ARE CHOSEN HERE, and none is seeded. Production targets are the owner's commercial
# commitment, not a constant a developer picked (§11.1). Until rows exist the engine resolves no policy and the
# desk says "no SLA policy applies" rather than implying a promise nobody made.
#
# THE MAPPING KEY IS `billing_plan_id`, NEVER A PLAN NAME. `billing_plans` has no `tier` and no `code`, and
# `name` is free text an operator may edit (db/schema.rb, billing_plans), so an id is the only stable key
# available. A NULL `billing_plan_id` is the installation default, and there may be exactly one of those -- a
# unique index on a NULL column would not enforce that, because Postgres treats NULLs as distinct, so the
# default row is constrained by a unique index on the EXPRESSION instead.
#
# `next_response_time_threshold` is deliberately absent: there is no `next_response_due_at` and no breach
# column anywhere in this schema, so the column could only have described a target nothing measures (§B-6).
#
# Thresholds are integer SECONDS, not the tenant SLA table's float. Sub-second precision is meaningless for a
# human response target, and a float threshold already forced a `.round` in the tenant clock.
class CreatePlatformSupportSlaPolicies < ActiveRecord::Migration[7.1]
  def change
    create_table :platform_support_sla_policies do |t|
      t.string :name, null: false
      t.string :description
      # Nullified rather than cascaded: retiring a plan must not silently delete the target that governed every
      # ticket raised while it existed, and `billing_plans` is restrict_with_error against subscriptions, so a
      # support policy must never become the reason a plan cannot be retired.
      t.references :billing_plan, index: false, foreign_key: { on_delete: :nullify }
      t.integer :first_response_time_threshold
      t.integer :resolution_time_threshold
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    # One policy per plan.
    add_index :platform_support_sla_policies, :billing_plan_id, unique: true,
                                                                where: 'billing_plan_id IS NOT NULL',
                                                                name: 'index_platform_support_sla_policies_on_plan'
    # One installation default. The indexed value is the constant `true` for every default row, so a second one
    # collides; a plain unique index on the nullable column would admit any number of them.
    add_index :platform_support_sla_policies, '(billing_plan_id IS NULL)', unique: true,
                                                                           where: 'billing_plan_id IS NULL',
                                                                           name: 'index_platform_support_sla_policies_on_default'
  end
end
