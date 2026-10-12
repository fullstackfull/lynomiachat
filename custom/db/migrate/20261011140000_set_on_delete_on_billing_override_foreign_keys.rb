# The two foreign keys on `billing_entitlement_overrides` were created without an `on_delete:`, so both are
# PostgreSQL's restricting default while every other foreign key this release adds names one
# (db/schema.rb: billing_subscriptions, campaign_recipients, commerce_carts, contact_identities,
# operations_signals, support_tickets all cascade or nullify).
#
# WHY THIS IS NEEDED
#   `granted_by_id` is the live problem. Nothing nullifies it -- the model declares
#   `belongs_to :granted_by, optional: true` and no `dependent:` anywhere points back at it -- so once a Super
#   Admin has granted an override, deleting that user's record is refused by the database. Agent removal
#   destroys users (Agents::DestroyJob, DeleteObjectJob), so this turns into a failed job rather than a message
#   anybody sees. An override is a commercial decision about an account and must outlive the person who made
#   it, which is exactly what nullify means.
#
#   `account_id` is defensive rather than live: `Custom::Account` declares
#   `has_many :billing_entitlement_overrides, dependent: :destroy`, so Rails already removes the rows before the
#   account row goes. It is brought into line anyway, because the cascade is the behaviour the table should have
#   whether or not a model happens to declare it, and because an operator reading schema.rb should not have to
#   hold two different rules for one table.
#
# ROLLBACK
#   Reversible: `change_table` with `remove_foreign_key`/`add_foreign_key` both ways. Reverting restores the
#   restricting default and with it the refused user delete, so there is nothing to undo in the data.
class SetOnDeleteOnBillingOverrideForeignKeys < ActiveRecord::Migration[7.1]
  def up
    remove_foreign_key :billing_entitlement_overrides, :accounts
    add_foreign_key :billing_entitlement_overrides, :accounts, on_delete: :cascade

    remove_foreign_key :billing_entitlement_overrides, :users, column: :granted_by_id
    add_foreign_key :billing_entitlement_overrides, :users, column: :granted_by_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :billing_entitlement_overrides, :accounts
    add_foreign_key :billing_entitlement_overrides, :accounts

    remove_foreign_key :billing_entitlement_overrides, :users, column: :granted_by_id
    add_foreign_key :billing_entitlement_overrides, :users, column: :granted_by_id
  end
end
