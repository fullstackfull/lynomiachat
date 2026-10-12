# DECISION 1's backward-compatibility vehicle.
#
# THE PROBLEM THIS SOLVES. Until this release the three `conversation_*` capabilities had no server-side effect
# on conversation access: the browser narrowed the list and the server returned everything in the holder's
# inboxes. Making them real means a set that names NONE of the three now means "no conversation access" -- which
# is the approved rule for a new set, and would be a silent removal of access for a set that already exists. A
# commerce-only or support-only set is a real thing the product invites an administrator to create, and its
# holders are working conversations today.
#
# THE RULE. This column says whether a set's conversation capabilities were chosen UNDER THE NEW SEMANTICS.
#
#   true   the set's conversation capabilities bind. Naming none of the three means no conversation access.
#   false  the set predates the semantics and names none of the three. Its holders keep the access they have.
#
# Every NEW set is `true` -- that is the column default, so absence is never read as unrestricted access for a
# set somebody configures from now on. An EXISTING set becomes `true` the moment an operator edits its
# conversation capabilities, which is the "explicitly edits" half of the decision and is done in the model
# (CustomRole#enforce_conversation_scope_on_explicit_edit) rather than here.
#
# THE BACKFILL, and why it is split. A set that ALREADY names one of the three is already explicit: its
# administrator chose "participating only" and the product's own UI has been showing them that narrowing all
# along, so the capability binding is what they already believe. Those rows stay `true`. Only the rows that name
# none of the three are grandfathered to `false`, because those are the only rows where the new rule would
# remove access nobody asked to remove.
#
# ADDITIVE AND REVERSIBLE. One column with a default. The old code does not read it. Rolling back leaves the
# column in place and unread, which is why `down` is a plain `remove_column`.
class AddConversationScopeEnforcedToCustomRoles < ActiveRecord::Migration[7.2]
  CONVERSATION_CAPABILITIES = %w[conversation_manage conversation_unassigned_manage conversation_participating_manage].freeze

  def up
    add_column :custom_roles, :conversation_scope_enforced, :boolean, default: true, null: false

    # `&&` is Postgres array overlap: true when the set names any of the three. The grandfathered rows are its
    # complement, and `permissions` may be NULL at the database level, so COALESCE rather than relying on the
    # column default.
    execute(<<~SQL.squish)
      UPDATE custom_roles
         SET conversation_scope_enforced = false
       WHERE NOT (COALESCE(permissions, '{}'::text[]) && ARRAY[#{CONVERSATION_CAPABILITIES.map { |c| "'#{c}'" }.join(',')}]::text[])
    SQL
  end

  def down
    remove_column :custom_roles, :conversation_scope_enforced
  end
end
