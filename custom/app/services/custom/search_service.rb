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

  # TENANTS READ DOCUMENTATION; THEY DO NOT AUTHOR IT, AND A DRAFT IS AUTHORING STATE.
  #
  # Every tenant portal, category and article route is closed by the three prepended Custom::*Policy modules,
  # because each of those controllers runs an unconditional `check_authorization`. `SearchController` runs none
  # and consults no policy at all, so this is the one documentation surface that choke point does not reach --
  # and `SearchService#filter_articles` was `current_account.articles.text_search(q)` with no status filter,
  # while the view renders the full body (app/views/api/v1/accounts/search/_article.json.jbuilder:4). Any
  # member -- administrator, agent, or a custom role holding knowledge_base_manage -- could read the workspace's
  # own draft and archived article bodies through it.
  #
  # Lynomia's own documentation is not reachable here at all: platform articles have `account_id` NULL and this
  # relation starts from `current_account.articles`. What leaked was the workspace's own frozen Help Center
  # content, so this is an authoring-state leak rather than a cross-tenant one.
  #
  # Published only, which is what the public renderer serves too
  # (Public::Api::V1::Portals::ArticlesController#set_article). Narrowing after `page`/`per` is deliberate and
  # correct: the condition lands in the WHERE clause, and Kaminari re-runs the same relation without its limit
  # for `total_count`, so the count agrees with the page instead of describing a wider set.
  def filter_articles
    @articles = super.published
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
