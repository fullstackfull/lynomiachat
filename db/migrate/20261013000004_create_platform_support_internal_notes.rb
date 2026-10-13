# Staff-only working notes on a Platform Support ticket -- never public
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M5).
#
# A SEPARATE TABLE, NEVER A VISIBILITY FLAG ON `platform_support_messages`. With one table and a flag, every
# count, every "last message" lookup, every search, every export and every endpoint written later has to carry
# the same four-word predicate, and each one is a place where omitting it discloses an internal note. With two
# tables there is no predicate to forget: the tenant controllers have no route that reaches this model, the
# tenant serializers have no key for it, and no tenant-visible object exposes an association to it.
#
# There is no `author_type`: a note is always written by a Lynomia agent, so the column would only ever hold one
# value. `agent_id` is NOT NULL and its foreign key takes NO ACTION on delete -- not cascade, which would erase
# who wrote the internal record of a decision, and not nullify, which the NOT NULL forbids. The consequence is
# deliberate: deleting the `users` row of an operator who has written notes fails loudly at the database rather
# than quietly removing their authorship, and an operator who should no longer work the desk is deactivated
# (`platform_support_agents.active`) rather than deleted.
#
# `has_many_attached :platform_support_note_files`. A note's attachment is staff-only BECAUSE OF ITS PARENT
# CLASS: the download endpoint authorizes the parent record through the tenant policy scope, which has no path
# to this table, so a tenant request for a note's attachment 404s as a consequence of that lookup rather than
# as a special case somebody has to remember.
class CreatePlatformSupportInternalNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :platform_support_internal_notes do |t|
      t.references :platform_support_ticket, null: false, index: false,
                                             foreign_key: { on_delete: :cascade }
      t.references :agent, null: false, index: false,
                           foreign_key: { to_table: :platform_support_agents }
      t.string :author_name, null: false
      t.text :body, null: false

      t.timestamps
    end

    # One ticket's notes, oldest first, which is the only read this table serves.
    add_index :platform_support_internal_notes, [:platform_support_ticket_id, :created_at],
              name: 'index_platform_support_notes_on_ticket_and_created_at'
    # Serves the foreign key's own delete check, which is what makes the NO ACTION above an indexed lookup
    # rather than a scan of every note.
    add_index :platform_support_internal_notes, :agent_id, name: 'index_platform_support_notes_on_agent'
  end
end
