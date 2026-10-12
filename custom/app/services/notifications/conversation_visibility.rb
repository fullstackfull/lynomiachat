# THE ONE DEFINITION of "may this membership see this notification", and the only place that decides it.
#
# THE RULE, in one line:
#
#     a conversation notification is visible  <=>  the member can currently access that conversation
#                                                  = the Inbox/Team/account ACCESS CEILING
#                                                    AND the conversation_* CAPABILITY scope
#
# Both layers, intersected. Neither replaces the other, and neither is restated here: the ceiling is
# `Conversations::AccessCeiling` (the rule `ConversationPolicy` has always applied, now held in one object and
# delegated to by that policy) and the capability is `Conversations::CapabilityScope`. This object's whole job
# is to compose them and to translate the composition onto the `notifications` table -- which column links a
# notification to a conversation, and what to do with a notification that is about something else.
#
# WHY IT EXISTS SEPARATELY FROM THOSE TWO. Four callers need that translation and they must not each write
# their own:
#
#   Custom::NotificationFinder                          the feed, `unread_count` and `count`, and through
#                                                       BaseListener the websocket's badge
#   Custom::Api::V1::Accounts::NotificationsController   the four member routes, by id
#   Custom::ActionCableListener                          the created/updated socket payload
#   Custom::Notification::DeleteNotificationJob          "delete all", so it cannot destroy what it cannot show
#
# `narrow` and `permits?` are the relation and the record shape of one question. They are composed from the
# same two objects, and the record shape is not a reimplementation at all: `permits?` asks
# `ConversationPolicy#show?`, which IS the product's canonical conversation access answer -- the ceiling
# through the delegation above, and the capability through `Custom::ConversationPolicy`. So the record path
# cannot drift from the rest of the product by construction, and the relation path is held to the same answer
# by an equivalence example that walks every combination.
#
# WHICH NOTIFICATIONS ARE "ABOUT A CONVERSATION".
#
#   Conversation  Every notification this product creates. All six `NotificationBuilder.new` call sites pass a
#                 Conversation (app/listeners/notification_listener.rb:7,21,42;
#                 app/services/messages/new_message_notification_service.rb:20,36;
#                 app/services/messages/mention_service.rb:55) and `Notification::PRIMARY_ACTORS` names only
#                 this one (app/models/notification.rb:56). Narrowed by the subselect below.
#
#   Message       HISTORICAL, and it is why this is a list rather than one string. `Message` still declares
#                 `has_many :notifications, as: :primary_actor` (app/models/message.rb:136) and
#                 `Migration::RemoveMessageNotifications` exists to delete the rows
#                 (app/jobs/migration/remove_message_notifications.rb:6), so a row could survive a lost
#                 enqueue. Such a row IS about a conversation -- the message's own -- but the notifications row
#                 does not say which, so it cannot be authorized from the relation. It is therefore EXCLUDED
#                 while narrowing is active rather than passed through: failing closed on a row we cannot
#                 authorize is the conservative direction, and it costs nothing, because the feed cannot render
#                 one anyway (`Notification#push_message_title` calls `display_id` on the primary actor and
#                 `Message` has no such method, so the index already raises on one today).
#
#   anything else Left alone, per the decision. Nothing creates one today; the three `sla_missed_*` enum values
#                 (app/models/notification.rb:44-46) are declared and have no creation site anywhere in app/,
#                 custom/ or lib/.
#
# NO ROW IS EVER WRITTEN OR DELETED HERE. This is a read-time answer, asked fresh every time. Access removed
# means hidden; access restored means visible again, from the same untouched row.
class Notifications::ConversationVisibility
  CONVERSATION_ACTOR = 'Conversation'.freeze

  # The primary-actor types that are ABOUT a conversation, and so are this rule's business.
  CONVERSATION_DERIVED_ACTORS = [CONVERSATION_ACTOR, 'Message'].freeze

  def self.for(account:, user:)
    new(account: account, user: user)
  end

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # True only when BOTH layers impose nothing, which in practice means an administrator (or an agent bot).
  # Callers check it first so that case costs no extra SQL.
  #
  # Note what is NOT unrestricted any more: a plain agent, and a holder of `conversation_manage`. The
  # capability layer says nothing about either, but the ceiling does -- they see the conversations of their
  # inboxes and teams, and no others. Before the ceiling was composed in, such a member was handed the whole
  # account's notifications.
  def unrestricted?
    capability_scope.unrestricted? && access_ceiling.unrestricted?
  end

  # The relation, narrowed. One uncorrelated subselect; never a check per row.
  def narrow(relation)
    return relation if unrestricted?

    relation.where.not(primary_actor_type: CONVERSATION_DERIVED_ACTORS)
            .or(relation.where(primary_actor_type: CONVERSATION_ACTOR, primary_actor_id: authorized_conversation_ids))
  end

  # The same question about one notification, so that an id is not a way around the relation.
  #
  # This asks the POLICY, not the two layers separately. `ConversationPolicy#show?` already composes them --
  # the administrator and agent-bot short-circuits, then `Conversations::AccessCeiling` through the delegation
  # in `Custom::ConversationPolicy`, then `Conversations::CapabilityScope` -- and it is what every other
  # conversation record read in the product is authorized by. Asking it means the notification record path is
  # the canonical answer rather than a copy of it, and it stays correct if either layer changes.
  def permits?(notification)
    return true unless CONVERSATION_DERIVED_ACTORS.include?(notification.primary_actor_type)
    return false unless notification.primary_actor_type == CONVERSATION_ACTOR

    conversation = notification.primary_actor
    return false if conversation.blank?

    ::ConversationPolicy.new(
      { user: @user, account: @account, account_user: account_user }, conversation
    ).show?
  end

  private

  # THE INTERSECTION, and the only place it is formed. Both narrowings are applied to the same relation, so
  # the result is the conversations that satisfy the ceiling AND the capability. Order is irrelevant; each is
  # an independent restriction.
  #
  # A relation, not an array: Rails renders it as `IN (SELECT "conversations"."id" ...)`, so the ids are never
  # loaded into Ruby and the answer cannot be bounded by how many conversations, inboxes or teams the member
  # can reach. For the capability's `:none` mode `narrow` returns `relation.none` and the subselect becomes
  # unsatisfiable, which is the right answer -- no conversation notification at all.
  def authorized_conversation_ids
    scope = capability_scope.narrow(@account.conversations, user: @user)
    access_ceiling.narrow(scope).select(:id)
  end

  def access_ceiling
    @access_ceiling ||= ::Conversations::AccessCeiling.for(account_user: account_user, user: @user, account: @account)
  end

  def capability_scope
    @capability_scope ||= ::Conversations::CapabilityScope.for(account_user)
  end

  # Read from the account being asked about, so a capability granted in one account cannot follow the user into
  # another. A user who is no longer a member resolves to nil, which `CapabilityScope` answers `:base` for --
  # the same answer it gives every other caller, and not a decision taken here.
  def account_user
    @account_user ||= @account.account_users.find_by(user_id: @user.id)
  end
end
