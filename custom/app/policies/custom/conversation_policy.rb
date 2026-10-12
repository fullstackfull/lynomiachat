# DECISION 1, the RECORD half: the capability narrowing applied to one conversation. Plus, since the
# notification access closure, the single delegation that gives the Inbox/Team ceiling one implementation.
#
# WHY BOTH HALVES ARE NEEDED. The list and the record are authorized by different objects -- the list by
# `Conversations::PermissionFilterService`, the record by `ConversationPolicy#show?` -- and narrowing only the
# list would leave `GET /api/v1/accounts/:id/conversations/:display_id` open. Everything hanging off a
# conversation goes through this one `show?`: its messages and their bodies, its attachments, its labels, its
# participants, its assignments, its draft messages, its commerce overview, its transcript, and the macro
# execution path. Narrowing here narrows all of them, which is why the decision pointed at this socket.
#
# IT ONLY EVER NARROWS. `super` runs first, so the administrator and agent-bot short-circuits and the
# inbox-or-team ceiling stay exactly as they are. The existing asymmetry between the two halves -- a team
# member with no inbox membership can open a conversation the list would never return, which
# spec/policies/conversation_policy_spec.rb asserts as intended -- is deliberately left alone: changing the
# ceiling is not part of this decision, and doing it here would narrow people for a reason nobody approved.
#
# WHAT THIS CLOSES, beyond the obvious. The write paths that hang off `show?` narrow with it, and one of them
# matters more than the rest: `toggle_status`'s self-assignment and the assignments endpoint were the way a
# participating-only holder could have granted themselves a conversation. Under this they cannot reach an
# unassigned conversation to self-assign it in the first place -- except with
# `conversation_unassigned_manage`, where reaching and taking unassigned work is the whole point of the
# capability.
#
# ---------------------------------------------------------------------------------------------------------
# THE CEILING DELEGATION, added by the notification access closure.
#
# `agent_can_view_conversation?` is where the Inbox/Team rule lived, as three private methods of a policy. A
# list cannot ask a policy per row, so the notification feed needed the same rule as a relation -- and writing
# one would have left the product with two interpretations of inbox-and-team visibility, which is the thing
# that goes wrong quietly. So the rule moved, whole, into `Conversations::AccessCeiling`, and this delegates to
# it. The policy stays the authority on conversation access; it no longer also stores the ceiling.
#
# The behaviour is unchanged by construction -- `AccessCeiling#agent_can_view?` is the same `inbox_access? ||
# team_access?` over the same two queries -- and three specs hold it to that:
# spec/policies/conversation_policy_spec.rb (this policy's own cases), the equivalence example in
# spec/services/conversations/access_ceiling_spec.rb (the relation and `show?` agreeing on every combination of
# inbox, team and role) and spec/requests/notification_access_ceiling_spec.rb (the feed and the by-id route
# agreeing over HTTP).
module Custom::ConversationPolicy
  def show?
    super && capability_scope.permits?(record, user: user)
  end

  private

  # Private, as it is on the class this is prepended to (conversation_policy.rb:14,16): a prepended module
  # carries its own visibility.
  def agent_can_view_conversation?
    access_ceiling.agent_can_view?(record)
  end

  def access_ceiling
    @access_ceiling ||= ::Conversations::AccessCeiling.for(account_user: account_user, user: user, account: account)
  end

  def capability_scope
    @capability_scope ||= ::Conversations::CapabilityScope.for(account_user)
  end
end
