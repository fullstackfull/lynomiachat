# DECISION 1, the RECORD half: the same capability narrowing applied to one conversation.
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
module Custom::ConversationPolicy
  def show?
    super && capability_scope.permits?(record, user: user)
  end

  private

  def capability_scope
    @capability_scope ||= ::Conversations::CapabilityScope.for(account_user)
  end
end
