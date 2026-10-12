# Rendered by name from OSS app/views/api/v1/models/_user.json.jbuilder:41, which is why this partial keeps
# this exact path (docs/p-final/clean-room/04-integration-contract.md §8).
#
# Two keys, and the second one is not optional. `custom_role_id` is what the browser reads to decide that a
# membership is a custom-role membership rather than a plain agent
# (app/javascript/dashboard/helper/permissionsHelper.js:21). The account switcher then shows the set's NAME in
# place of the built-in role, reading `account.custom_role.name` with no guard at all
# (app/javascript/dashboard/components-next/sidebar/SidebarAccountSwitcher.vue:121-124) -- so a membership that
# reported only the id would make the switcher throw.
#
# The set's capabilities are not repeated here: they are already in the `permissions` key the surrounding view
# emits, and one list is one place for the two to agree.
json.custom_role_id account_user.custom_role_id

if account_user.custom_role.present?
  json.custom_role do
    json.id account_user.custom_role.id
    json.name account_user.custom_role.name
  end
end
