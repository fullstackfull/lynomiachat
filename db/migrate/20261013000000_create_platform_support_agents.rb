# Who, on Lynomia's side, may work the Platform Support desk
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M1).
#
# WHY A TABLE AND NOT A ROLE ON `users`. Being a Super Admin is not being support staff: the console is reached
# by everyone who administers this installation, and the desk reads every tenant's complaints. So staff
# authority is a row somebody deliberately created, and the desk refuses every action until one exists. No row
# is seeded by this migration or by any seeder -- who the first agents are is an owner decision
# (§11.3), and inventing one would hand the desk to whoever happens to hold a console login.
#
# `display_name` is a snapshot of User#available_name, refreshed whenever the row is saved. It exists so an
# internal note and an event stay attributable without a join, which is the rule Custom::AuditLog#username
# already applies to every audit row.
#
# `role` is the ONLY capability distinction in V1: a `lead` may reassign another agent's ticket and edit SLA
# policies. Anything finer is a later phase, and a finer vocabulary invented now would be one nobody has used.
#
# ROLLBACK drops the table. Tickets survive: `platform_support_tickets.assignee_id` is nullified by its own
# foreign key, so an unassigned queue is the worst outcome.
class CreatePlatformSupportAgents < ActiveRecord::Migration[7.1]
  def change
    create_table :platform_support_agents do |t|
      # One staff row per person, enforced by the index rather than by convention: two rows would make "which
      # role does this operator have" ambiguous. Cascades, because a staff row for a user who no longer exists
      # is not a fact about anybody.
      t.references :user, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.integer :role, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.string :display_name, null: false

      t.timestamps
    end
  end
end
