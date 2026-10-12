# DECISION 1, the SEARCH half -- the hole that neither of the other two closes.
#
# `SearchService` never calls `Conversations::PermissionFilterService`. It builds its own scope from
# `accessable_inbox_ids` (app/services/search_service.rb:25-27) and narrows conversations at :34 and messages
# at :110-112, so fixing the list relation and the record policy and stopping there would leave
# `GET /api/v1/accounts/:id/search` and `/search/messages` returning conversations and MESSAGE BODIES with no
# capability narrowing at all. The decision asks for list, search and count to agree; this is the search leg.
#
# There is a second reason this leg needs its own fix. `should_skip_inbox_filtering?` (:152-154) drops the
# message inbox filter not only for an administrator but for `user_has_access_to_all_inboxes?` (:156-158) -- any
# user who happens to belong to every inbox in the account, which on a small installation is an ordinary agent.
# The narrowing below is by assignee and is applied independently of that skip, so it holds either way.
#
# COUNTS AGREE TOO, because Kaminari's `total_count` re-runs the same relation without its limit: narrowing the
# relation narrows the count with it, rather than paging a wider set.
module Custom::SearchService
  def filter_conversations
    @conversations = capability_scope.narrow(super, user: current_user)
  end

  private

  # Messages are narrowed by the conversation they belong to, which is the only honest way to express a rule
  # about conversations over a message relation. A subquery rather than a join, so the existing message filters
  # and the GIN/Elasticsearch variants are untouched -- all three build on this one method.
  def message_base_query
    return super if capability_scope.unrestricted?
    return super.none if capability_scope.none?

    super.where(conversation_id: visible_conversation_ids)
  end

  def visible_conversation_ids
    capability_scope.narrow(current_account.conversations, user: current_user).select(:id)
  end

  def capability_scope
    @capability_scope ||= ::Conversations::CapabilityScope.for(account_user)
  end
end
