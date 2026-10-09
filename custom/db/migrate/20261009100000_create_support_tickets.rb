# Lynomia Support: one row is one support case (docs/p9/01-architecture.md §3).
#
# This table exists because a Conversation cannot be a support case. `conversations.inbox_id` is NOT NULL
# (db/schema.rb:1024) and `contact_id` is validated present (app/models/conversation.rb:78) and dereferenced in
# before_create (:308) -- while an internal operational case has no customer and no channel. So the three links a
# conversation requires are exactly the three this table makes optional.
#
# It holds the CASE and never the conversation: no message body, no attachment, no provider payload, no
# credential. The messaging stays in Chatwoot messages, the customer identity stays on the contact, and the
# channel identity stays on the inbox.
class CreateSupportTickets < ActiveRecord::Migration[7.2]
  def change
    create_tickets
    add_ticket_indexes
    create_ticket_events
  end

  private

  def create_tickets
    create_table :support_tickets do |t|
      ticket_identity(t)
      ticket_links(t)
      ticket_sla(t)
      ticket_lifecycle(t)
    end
  end

  def ticket_identity(table)
    table.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
    table.integer :reference_number, null: false
    table.string :title, null: false
    table.text :description
    table.string :category, null: false, default: 'other'
    table.integer :status, null: false, default: 0
    table.integer :priority, null: false, default: 1
  end

  # The first three are nullable on purpose, and are the whole reason this table exists.
  def ticket_links(table)
    table.references :conversation, index: false, foreign_key: { on_delete: :nullify }
    table.references :contact, index: false, foreign_key: { on_delete: :nullify }
    table.references :inbox, index: false, foreign_key: { on_delete: :nullify }
    table.references :assignee, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
    table.references :team, index: false, foreign_key: { on_delete: :nullify }
    # Never accepted from the client; nil for an operator-created or system-created case.
    table.references :created_by, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
    # The operational origin. A string column with an allow-list validation rather than a Rails polymorphic
    # association, because nothing in this repository constrains a polymorphic type column and an unconstrained
    # one is a class name the client chooses (docs/p9/00-discovery.md §10).
    table.string :source_type
    table.bigint :source_id
  end

  # The policy lives in the existing, previously unused `sla_policies` table; the per-case clock lives here
  # because applied_slas.conversation_id is NOT NULL (db/schema.rb:181) and cannot hold a ticket's state.
  def ticket_sla(table)
    table.references :sla_policy, index: false, foreign_key: { on_delete: :nullify }
    table.datetime :first_response_due_at
    table.datetime :resolution_due_at
    table.datetime :first_responded_at
    table.datetime :first_response_breached_at
    table.datetime :resolution_breached_at
    table.datetime :sla_paused_at
    table.integer :sla_paused_seconds, null: false, default: 0
  end

  def ticket_lifecycle(table)
    table.datetime :last_activity_at, null: false
    table.datetime :resolved_at
    table.datetime :closed_at
    table.timestamps
  end

  # Seven indexes, chosen from the query shapes the product actually issues rather than one per filter. The
  # reasoning, and the two indexes deliberately left out, are in docs/p9/01-architecture.md §3.
  def add_ticket_indexes
    add_index :support_tickets, [:account_id, :reference_number], unique: true,
                                                                  name: 'index_support_tickets_on_account_and_reference'
    add_index :support_tickets, [:account_id, :status, :last_activity_at],
              order: { last_activity_at: :desc }, name: 'index_support_tickets_on_account_status_activity'
    add_index :support_tickets, [:account_id, :assignee_id, :status], name: 'index_support_tickets_on_account_assignee_status'
    add_index :support_tickets, [:account_id, :team_id, :status], name: 'index_support_tickets_on_account_team_status'
    add_index :support_tickets, :conversation_id
    add_index :support_tickets, :contact_id
    # The two queries that run on a SCHEDULE ACROSS EVERY ACCOUNT, which is why each gets a partial index
    # holding only the rows it can ever match rather than relying on the per-account indexes above. 4 and 5 are
    # resolved and closed, so `status < 4` is "still active".
    #
    # The first also serves the workspace's Overdue view.
    add_index :support_tickets, [:account_id, :resolution_due_at],
              where: 'resolution_due_at IS NOT NULL AND resolution_breached_at IS NULL AND status < 4',
              name: 'index_support_tickets_on_open_resolution_due'
    add_index :support_tickets, [:account_id, :first_response_due_at],
              where: 'first_response_due_at IS NOT NULL AND first_responded_at IS NULL ' \
                     'AND first_response_breached_at IS NULL AND status < 4',
              name: 'index_support_tickets_on_awaiting_first_response'
  end

  # History and internal notes in one table, because an internal note IS an entry in the case's history and two
  # tables would mean two orderings to merge. `data` is jsonb with no ActiveRecord store, so it stays queryable --
  # the trap messages.content_attributes falls into (app/models/message.rb:112) is avoided by not repeating it.
  def create_ticket_events
    create_table :support_ticket_events do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :support_ticket, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :user, index: false, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :event_type, null: false
      t.text :body
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end

    add_index :support_ticket_events, [:support_ticket_id, :created_at], name: 'index_support_ticket_events_on_ticket_and_created_at'
    add_index :support_ticket_events, [:account_id, :created_at], name: 'index_support_ticket_events_on_account_and_created_at'
  end
end
