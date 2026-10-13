# One ticket's history, with tenant visibility as a POSITIVE allow-list
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M6).
#
# WHY NO `visibility` COLUMN. A column defaults to something, and whatever it defaults to is what a future
# contributor gets by forgetting. PlatformSupport::Event::CUSTOMER_VISIBLE_EVENT_TYPES names 7 of the 18 types,
# so an event type added in a later phase is invisible to the customer until somebody deliberately lists it.
# What is excluded, and why: `assigned` and `unassigned` (which operator holds a ticket is internal),
# `internal_note_added` (the EXISTENCE of a note is internal), `priority_changed` (internal triage),
# `subject_changed` and `category_changed` (triage again), every `sla_*` (Lynomia's internal commitments, which
# publishing would turn into a contractual claim), and `account_deleted`.
#
# `metadata` holds the structured before/after values the operator view reads. It is NEVER serialized to the
# tenant -- the tenant event partial has no key for it -- and PlatformSupport::EventRecorder is the only writer,
# with a fixed payload shape per event type, so no caller can hand it a free-form hash. Ids, enum values,
# counts and timestamps only: no message body, no provider payload, no credential.
#
# `actor_type` is the same three-value allow-list the thread uses and is not a polymorphic association, for the
# same reason: `System` is not a record. `actor_name` is the snapshot that keeps a row attributable after the
# person's row is gone, and the tenant serializer does not emit it for operator-side events.
#
# `created_at` only, with no `updated_at`: a history row is written once and never edited.
class CreatePlatformSupportEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :platform_support_events do |t|
      t.references :platform_support_ticket, null: false, index: false,
                                             foreign_key: { on_delete: :cascade }
      t.string :event_type, null: false
      t.string :actor_type
      t.bigint :actor_id
      t.string :actor_name
      t.jsonb :metadata, default: {}, null: false
      t.datetime :created_at, null: false
    end

    # One ticket's history, oldest first.
    add_index :platform_support_events, [:platform_support_ticket_id, :created_at],
              name: 'index_platform_support_events_on_ticket_and_created_at'
  end
end
