# One complaint a customer raised with Lynomia itself
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M3).
#
# WHY NOT `support_tickets`. That table is the tenant's own helpdesk and cannot carry this product, re-verified
# line by line at this baseline (§9): its assignee must be an AccountUser of the customer's account, so a
# Lynomia operator could only be assigned by joining the customer's account; its policy gives every tenant
# administrator `manage_all?`, so the customer could edit Lynomia's rows; its `account_id` is NOT NULL and
# cascades, so a churned customer's complaint history dies with them; it has no staff-private note; and its
# `audited associated_with: :account` would publish operator activity into the customer's own audit log.
#
# `account_id` IS NULLABLE ON PURPOSE. It is the SUBJECT account, not an owner. The model requires it on create
# so a live ticket always has a subject, and the foreign key nullifies on delete so a deleted account ORPHANS
# the history rather than erasing it -- while the tenant policy scope, which matches on a concrete account id,
# can never read an orphan. `account_name_at_creation` keeps the row attributable afterwards.
#
# `reporter_name` is the ONLY personal-data snapshot on this table, and it is the minimum that keeps a thread
# attributable after the person's user row is deleted -- the same rule Custom::AuditLog#capture_actor_name
# already applies to every audit row. `reporter_email` MUST NEVER BE ADDED (§1 M3, D-4): the live address is
# reachable through `reporter_id` while the user exists, and once it does not there is nobody to reply to.
#
# `reference_number` is GLOBALLY unique, which is what makes `LYN-000123` resolve to one ticket on a phone call
# with no "which account?" follow-up. The `LYN-` prefix and the padding are presentation and live in
# PlatformSupport::Ticket#reference, so changing them never needs a migration.
#
# `status < 4` in three of the partial indexes below is why `resolved` and `closed` are numbered last. Same
# convention, and the same reason, as the tenant table.
#
# ROLLBACK drops the table, and its cascades take the thread, the notes and the history with it. Operator
# accountability survives independently in `audits`, which carries no foreign key to anything here.
class CreatePlatformSupportTickets < ActiveRecord::Migration[7.1]
  # Thirty columns and seven indexes in one reversible definition. Metrics has no useful opinion about the
  # shape of a schema, and `.rubocop.yml` is not this module's file to edit.
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :platform_support_tickets do |t|
      t.integer :reference_number, null: false
      t.references :account, index: false, foreign_key: { on_delete: :nullify }
      t.string :account_name_at_creation, null: false
      t.references :reporter, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :reporter_name, null: false

      t.string :category, null: false, default: 'other'
      t.string :subject, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.integer :priority, null: false, default: 1

      # An assignee can only ever be a Lynomia staff row. The foreign key is what makes that structural: a
      # tenant user id cannot be written here at all, so no AccountUser membership is ever needed for staff.
      t.references :assignee, index: false, foreign_key: { to_table: :platform_support_agents, on_delete: :nullify }
      t.references :sla_policy, index: false,
                                foreign_key: { to_table: :platform_support_sla_policies, on_delete: :nullify }

      # Commercial state as it was when the complaint was made. No personal data, and required for honest SLA
      # resolution and analytics after a plan is renamed or retired.
      t.bigint :plan_id_at_creation
      t.string :plan_name_at_creation
      t.string :subscription_status_at_creation

      t.datetime :first_response_due_at
      t.datetime :resolution_due_at
      t.datetime :first_responded_at
      t.datetime :first_response_breached_at
      t.datetime :resolution_breached_at
      t.datetime :sla_paused_at
      t.integer :sla_paused_seconds, null: false, default: 0

      t.datetime :last_customer_message_at
      t.datetime :last_operator_message_at
      # What clears the tenant's unread dot, so the dot needs no notification row to exist.
      t.datetime :customer_last_viewed_at
      t.datetime :last_activity_at, null: false
      t.datetime :resolved_at
      t.datetime :closed_at

      t.timestamps
    end

    add_foreign_key :platform_support_tickets, :billing_plans, column: :plan_id_at_creation, on_delete: :nullify

    # What makes a global reference true rather than hoped.
    add_index :platform_support_tickets, :reference_number, unique: true,
                                                            name: 'index_platform_support_tickets_on_reference'
    # The tenant's list, which is always filtered by account first.
    add_index :platform_support_tickets, [:account_id, :last_activity_at],
              order: { last_activity_at: :desc },
              name: 'index_platform_support_tickets_on_account_and_activity'
    # "My queue".
    add_index :platform_support_tickets, [:assignee_id, :status],
              name: 'index_platform_support_tickets_on_assignee_and_status'
    # The staff queue's default ordering.
    add_index :platform_support_tickets, [:status, :priority, :last_activity_at],
              order: { last_activity_at: :desc },
              name: 'index_platform_support_tickets_on_queue_order'
    # The SLA sweep's two reads. Each partial index carries the same predicates the sweep asks for, because a
    # query that does not ask for them cannot use the index at all.
    add_index :platform_support_tickets, :resolution_due_at,
              where: 'resolution_due_at IS NOT NULL AND resolution_breached_at IS NULL AND status < 4',
              name: 'index_platform_support_tickets_on_open_resolution_due'
    add_index :platform_support_tickets, :first_response_due_at,
              where: 'first_response_due_at IS NOT NULL AND first_responded_at IS NULL ' \
                     'AND first_response_breached_at IS NULL AND status < 4',
              name: 'index_platform_support_tickets_on_awaiting_first_response'
    # The unassigned queue, which is the first thing an operator opens. Its KEY is the queue's ORDER BY and
    # its PREDICATE is the only thing that view always says, because a partial index is used only when the
    # query implies its predicate: `?assignee_id=unassigned` adds no status clause (the operator has not
    # filtered one, and the view must still show unassigned resolved and closed tickets), so an index
    # predicated on `status < 4` could never serve it. Measured on 40k rows, 26.7k of them unassigned:
    # 767 buffers and 4.15ms through the queue-order index with a discard filter and an incremental sort,
    # against 7 buffers and 0.06ms through this one, with no sort at all.
    add_index :platform_support_tickets, [:status, :priority, :last_activity_at],
              order: { priority: :desc, last_activity_at: :desc },
              where: 'assignee_id IS NULL',
              name: 'index_platform_support_tickets_on_unassigned'
  end
end
