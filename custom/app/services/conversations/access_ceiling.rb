# THE ONE EXPRESSION of the Inbox/Team conversation access ceiling, in both the shapes the product needs.
#
# WHY IT EXISTS. The ceiling was only ever a record predicate, living in three private methods of
# `ConversationPolicy` (app/policies/conversation_policy.rb:16-36). That is fine for authorizing one
# conversation and useless for authorizing a list, so the notification feed -- which must not ask a policy per
# row -- had no way to apply it and did not. This object holds the rule once and offers it as a record answer
# AND as a relation, so the two cannot disagree.
#
# IT IS NOT A NEW RULE. `agent_can_view?` is a verbatim move of `ConversationPolicy#agent_can_view_conversation?`
# with the same two queries, and `Custom::ConversationPolicy` now delegates that method here rather than
# keeping a second copy. So there is one implementation, and the policy -- still the product's authority on
# conversation access -- is its only record-path caller.
#
# THE RULE, exactly as it already was:
#
#   administrator        every conversation in the account. `account_user&.administrator?`, the `role` column,
#                        which is how administrator is decided everywhere in this product.
#   agent bot           every conversation. `user.is_a?(AgentBot)`; a bot is not a membership.
#   inbox membership    a conversation in an inbox the user belongs to, through `inbox_members`
#                       (`user.inboxes`, app/models/user.rb:100), scoped to this account.
#   team membership     a conversation whose `team_id` is set AND is a team the user belongs to, through
#                       `team_members` (`user.teams`, app/models/user.rb:113), scoped to this account.
#   inbox OR team       either is sufficient. They are not required together and neither is required.
#
# WHAT IS DELIBERATELY NOT IN IT, because it is not in the policy either: being the ASSIGNEE grants nothing on
# its own, and neither does being a participant. `ConversationPolicy` defines `assigned_to_user?` (:38-40) and
# `participant?` (:42-44) and calls neither from `show?`. An assignee who is not an inbox member, on a
# conversation with no team, is refused -- today, and still. Nothing here widens that.
#
# AN UNASSIGNED CONVERSATION is not a special case: the ceiling never looks at `assignee_id`. That is the
# capability layer's question (`Conversations::CapabilityScope`), and the two layers are composed rather than
# merged -- see `Notifications::ConversationVisibility`.
#
# A nil `account` is preserved rather than guarded: the policy writes `where(account_id: account&.id)`, which
# matches nothing, so both legs are false. This does the same thing for the same reason.
class Conversations::AccessCeiling
  def self.for(account_user:, user:, account:)
    new(account_user: account_user, user: user, account: account)
  end

  def initialize(account_user:, user:, account:)
    @account_user = account_user
    @user = user
    @account = account
  end

  # True when the ceiling imposes nothing -- the two cases `ConversationPolicy#show?` short-circuits on before
  # it ever asks about inbox or team (conversation_policy.rb:11).
  def unrestricted?
    @account_user&.administrator? || @user.is_a?(AgentBot)
  end

  # The record answer, and the only thing `Custom::ConversationPolicy` delegates. Named after the method it
  # replaces so the correspondence is impossible to miss.
  def agent_can_view?(conversation)
    inbox_access?(conversation) || team_access?(conversation)
  end

  # The same rule as a relation, which is what a list needs. `show?` in full: unrestricted for an administrator
  # or a bot, otherwise inbox OR team.
  #
  # `team_id IN (<subquery>)` carries the policy's `return false if record.team_id.blank?` for free, because
  # `NULL IN (...)` is never true. The ids are relations rather than arrays, so both legs are subselects and
  # neither is bounded by how many inboxes or teams the member belongs to.
  def narrow(relation)
    return relation if unrestricted?

    relation.where(inbox_id: accessible_inbox_ids).or(relation.where(team_id: accessible_team_ids))
  end

  private

  def inbox_access?(conversation)
    accessible_inboxes.exists?(id: conversation.inbox_id)
  end

  def team_access?(conversation)
    return false if conversation.team_id.blank?

    accessible_teams.exists?(id: conversation.team_id)
  end

  def accessible_inboxes
    @accessible_inboxes ||= @user.inboxes.where(account_id: @account&.id)
  end

  def accessible_teams
    @accessible_teams ||= @user.teams.where(account_id: @account&.id)
  end

  def accessible_inbox_ids
    accessible_inboxes.select(:id)
  end

  def accessible_team_ids
    accessible_teams.select(:id)
  end
end
