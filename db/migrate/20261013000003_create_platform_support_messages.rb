# The public thread on a Platform Support ticket -- public, always
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M4).
#
# EVERY ROW IN THIS TABLE IS VISIBLE TO THE CUSTOMER. There is no visibility column and there will not be one:
# an internal note is a row in `platform_support_internal_notes`, a different table the tenant's query objects
# have no association, no model constant and no table name for. Secrecy that is a predicate is secrecy somebody
# eventually forgets to add; secrecy that is a table is a join nobody made.
#
# `author_type` is a frozen allow-list of three strings and is NOT a polymorphic association, because `System`
# is not a record: it is how the product itself speaks in a thread. `author_id` is therefore NULL for `System`
# and set for the other two. `author_name` is the snapshot, for the same reason it is on the ticket -- and the
# tenant serializer never emits it for an operator message, substituting the literal "Lynomia Support", so no
# individual operator is ever named to a customer.
#
# `body` is `text` holding PLAIN TEXT. There is no HTML column, no markdown column and no rich editor anywhere
# in this module, which is the whole of its XSS story: Vue interpolation and ERB both escape by default, so
# there is nothing to sanitize because nothing is expected to be markup.
#
# Attachments arrive through `has_many_attached :platform_support_message_files` and are reachable ONLY through
# the module's own authorized download endpoint. No serializer emits a blob URL: blob URLs do not expire in
# this installation, so a signed id in a JSON response would be a permanent bearer token.
class CreatePlatformSupportMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :platform_support_messages do |t|
      t.references :platform_support_ticket, null: false, index: false,
                                             foreign_key: { on_delete: :cascade }
      t.string :author_type, null: false
      t.bigint :author_id
      t.string :author_name, null: false
      t.text :body, null: false

      t.timestamps
    end

    # The only read this table serves: one ticket's thread, oldest first.
    add_index :platform_support_messages, [:platform_support_ticket_id, :created_at],
              name: 'index_platform_support_messages_on_ticket_and_created_at'
  end
end
