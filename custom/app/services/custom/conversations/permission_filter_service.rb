# DECISION 1, the LIST half: the capability narrowing applied to the one relation almost every conversation
# read goes through.
#
# `Conversations::PermissionFilterService` is the choke point for the conversation list, the meta counts, the
# filter endpoint, the conversation search endpoint, a contact's conversations and attachments, the contact
# activity timeline, bulk actions, and the saved-filter counters. Narrowing here narrows all of them at once,
# which is why the decision asked for the existing socket rather than a new framework.
#
# IT ONLY EVER NARROWS. `super` is called first and its result is intersected, so the inbox-membership ceiling
# the service already imposes (and the query-plan hint variant of it) stays exactly as it is -- including the
# administrator short-circuit, which returns before any of this and must, because an administrator's reach is
# the `role` column everywhere in this product.
#
# WHAT THIS DOES NOT FIX, stated so the next reader does not assume it did. Two paths do not come through
# here and are handled separately: the record path, which is `ConversationPolicy#show?`
# (custom/app/policies/custom/conversation_policy.rb), and global search, which never calls this service at all
# (custom/app/services/custom/search_service.rb). The unread counter has its own expression of the same rule and
# now reads it from the same object.
module Custom::Conversations::PermissionFilterService
  def perform
    capability_scope.narrow(super, user: user)
  end

  private

  # The membership, read the way the service already reads it, so the capability answer and the
  # administrator answer come from the same row.
  def capability_scope
    @capability_scope ||= ::Conversations::CapabilityScope.for(account_user)
  end
end
