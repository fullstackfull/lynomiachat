# The one list every capability check in the product reads
# (docs/p-final/clean-room/specs/C-account-role-permissions.md §4).
#
# Three clean Lynomia policies consult it -- Commerce::ActionPolicy, Support::TicketPolicy and
# Custom::ContactPolicy -- and so does app/views/api/v1/models/_user.json.jbuilder, which is how the browser
# learns what to offer. Conversations::CapabilityScope reads it too (DECISION 1). There is deliberately no
# second way to ask the question.
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
#
# ---------------------------------------------------------------------------------------------------------
# DECISION 2. ENTITLEMENT IS A HARD UPPER BOUND, AND THIS IS THE ONE PLACE IT IS EXPRESSED.
#
# Effective permission = installation availability AND account entitlement AND member/role permission. The
# first two are what `Billing::Entitlements.allowed?` already answers, in the product's own precedence --
# system feature, then operator override, then the account's feature bits, which is where
# `Billing::FeatureSync` writes what the plan bought (custom/app/services/billing/entitlements.rb:9-23). So
# this is not a second commercial system; it is the existing one, consulted at the single choke point every
# capability reader already goes through. Nothing is scattered into controllers.
#
# WHAT A LAPSE DOES, and what it deliberately does not do:
#
#   * STORED SETS AND ASSIGNMENTS ARE UNTOUCHED. No row is deleted and no membership is detached. The set is
#     still there, still attached, and starts granting again the moment the entitlement returns -- which is the
#     reactivation the decision asks for, with no restore step.
#   * THE FALLBACK IS `super`, which is the member's BUILT-IN ROLE list. For a membership holding a set that is
#     always `agent`, because the attachment path forces the column
#     (custom/app/controllers/custom/api/v1/accounts/agents_controller.rb:56) and upstream's builder defaults
#     it. So the fallback is strictly narrower than any set -- a set can only ever have ADDED to the agent
#     baseline -- and it cannot reach administrator, because administrator is the `role` column and this list
#     is not consulted for it anywhere.
#   * CAPABILITIES WITH THEIR OWN GATE KEEP IT. `commerce_order_manage` is still gated by `lynomia_commerce` at
#     its own controller and `support_ticket_manage` by `lynomia_support_tickets` at its own base controller.
#     This bound sits above those, not instead of them.
#   * CONTACT MERGE GETS NO NEW PAID FEATURE. `contact_manage` remains the authoritative control for it, as
#     decided.
#
# WHY DEPLOYING THIS CHANGES NOTHING TODAY. `Billing::Entitlements.allowed?` for a non-system capability is the
# override, then `account.feature_enabled?`. While commercial enforcement is off every subscription is
# accessible and no plan withholds anything, so the answer is the account's own flag -- exactly what decides
# whether the set could be administered in the first place. The behaviour only diverges for an account that has
# actually lost the flag, which is the case this exists for.
module Custom::AccountUser
  CUSTOM_ROLE_MARKER = 'custom_role'.freeze

  # The capability that sells permission sets. Named here because this is the file that enforces it.
  CUSTOM_ROLES_CAPABILITY = 'custom_roles'.freeze

  def permissions
    return super if custom_role.blank?
    return super unless account_entitled_to_custom_roles?

    custom_role.permissions + [CUSTOM_ROLE_MARKER]
  end

  private

  # `account` rather than `custom_role.account`: the membership's account is the one being billed, and reading
  # it through the set would answer a question about the set's owner instead.
  def account_entitled_to_custom_roles?
    ::Billing::Entitlements.allowed?(account, CUSTOM_ROLES_CAPABILITY)
  end
end
