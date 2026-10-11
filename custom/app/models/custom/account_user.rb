# The one list every capability check in the product reads
# (docs/p-final/clean-room/specs/C-account-role-permissions.md §4).
#
# Three clean Lynomia policies consult it -- Commerce::ActionPolicy, Support::TicketPolicy and
# Custom::ContactPolicy -- and so does app/views/api/v1/models/_user.json.jbuilder, which is how the browser
# learns what to offer. There is deliberately no second way to ask the question.
#
# The rule: a membership with a set attached has that set's capabilities, plus a marker saying it has one; a
# membership with none falls through to the list Chatwoot derives from its built-in role.
#
# The marker is what `getUserRole` reads to decide that such a membership is a custom-role membership rather
# than a plain agent (app/javascript/dashboard/helper/permissionsHelper.js:19-26), and what the route and
# command permission lists match on.
#
# Attaching a set never widens or narrows what an administrator may do on the server: every administrator check
# in the product reads the `role` column through `administrator?`, not this list.
module Custom::AccountUser
  CUSTOM_ROLE_MARKER = 'custom_role'.freeze

  def permissions
    return super if custom_role.blank?

    custom_role.permissions + [CUSTOM_ROLE_MARKER]
  end
end
