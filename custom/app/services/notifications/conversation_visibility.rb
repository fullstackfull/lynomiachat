# THE ONE DEFINITION of "may this membership see this notification", and the only place that decides it.
#
# WHY IT EXISTS SEPARATELY FROM `Conversations::CapabilityScope`. The capability rule itself -- what
# `conversation_manage`, `conversation_unassigned_manage` and `conversation_participating_manage` mean, widest
# wins, grandfathering, D2's entitlement bound -- lives in `Conversations::CapabilityScope` and is NOT restated
# here. What is here is the translation of that rule onto the `notifications` table: which column links a
# notification to a conversation, and what to do with a notification that is about something else. Four callers
# need that translation and they must not each write their own:
#
#   Custom::NotificationFinder                          the feed, `unread_count` and `count`, and through
#                                                       BaseListener the websocket's badge
#   Custom::Api::V1::Accounts::NotificationsController   the four member routes, by id
#   Custom::ActionCableListener                          the created/updated socket payload
#   Custom::Notification::DeleteNotificationJob          "delete all", so it cannot destroy what it cannot show
#
# `narrow` and `permits?` are deliberately the same pair of shapes `CapabilityScope` offers, and they are
# derived from the same object, so the relation answer and the record answer cannot drift.
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

  # True when this membership is not narrowed at all -- an administrator, a membership with no set attached, a
  # set holding `conversation_manage`, a grandfathered set, or an account whose `custom_roles` entitlement has
  # lapsed. Callers check it first so the unrestricted case costs no extra SQL.
  def unrestricted?
    capability_scope.unrestricted?
  end

  # The relation, narrowed. One uncorrelated subselect; never a check per row.
  def narrow(relation)
    return relation if unrestricted?

    relation.where.not(primary_actor_type: CONVERSATION_DERIVED_ACTORS)
            .or(relation.where(primary_actor_type: CONVERSATION_ACTOR, primary_actor_id: authorized_conversation_ids))
  end

  # The same question about one notification, so that an id is not a way around the relation.
  def permits?(notification)
    return true if unrestricted?
    return true unless CONVERSATION_DERIVED_ACTORS.include?(notification.primary_actor_type)
    return false unless notification.primary_actor_type == CONVERSATION_ACTOR

    conversation = notification.primary_actor
    return false if conversation.blank?

    capability_scope.permits?(conversation, user: @user)
  end

  private

  # A relation, not an array: Rails renders it as `IN (SELECT "conversations"."id" ...)`, so the ids are never
  # loaded into Ruby and the answer cannot be bounded by how many conversations the member can reach. For the
  # `:none` mode `narrow` returns `relation.none` and the subselect becomes unsatisfiable, which is the right
  # answer -- no conversation notification at all.
  def authorized_conversation_ids
    capability_scope.narrow(@account.conversations, user: @user).select(:id)
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
