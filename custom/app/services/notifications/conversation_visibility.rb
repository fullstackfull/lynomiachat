# THE ONE DEFINITION of "may this membership see this notification", and the only place that decides it.
#
# THE RULE, in one line:
#
#     a conversation notification is visible  <=>  the member can currently access that conversation
#                                                  = the Inbox/Team/account ACCESS CEILING
#                                                    AND the conversation_* CAPABILITY scope
#
# ONE MORE ACTOR TYPE NOW EXISTS, with its own rule rather than a share of this one:
#
#     a platform support notification is visible  <=>  PlatformSupport::TicketPolicy lets this member read
#                                                      that ticket (account predicate included)
#
# The two rules never mix. See VISIBLE_ACTOR_TYPES, and the per-type branches in `narrow` and `permits?`.
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
# FAIL-CLOSED, BY A POSITIVE ALLOW-LIST. See VISIBLE_ACTOR_TYPES: a notification whose primary actor is not a
# type this object names is refused, for every member, administrators included. There is no pass-through.
#
# NO ROW IS EVER WRITTEN OR DELETED HERE. This is a read-time answer, asked fresh every time. Access removed
# means hidden; access restored means visible again, from the same untouched row.
class Notifications::ConversationVisibility
  CONVERSATION_ACTOR = 'Conversation'.freeze
  PLATFORM_SUPPORT_TICKET_ACTOR = 'PlatformSupport::Ticket'.freeze

  # THE ALLOW-LIST, and the whole of the answer to "which notifications may a member be shown".
  #
  # POSITIVE AND CLOSED. Only a notification whose `primary_actor_type` is named here may be shown -- to ANY
  # member, an administrator included -- and every type named here is authorized by the conversation rule
  # above. A type that is not named is refused, with no default to fall back on.
  #
  # WHAT THIS REPLACES, AND WHY. `narrow` used to read
  # `where.not(primary_actor_type: [Conversation, Message]).or(...)` and `permits?` used to `return true
  # unless` that list included the type. So any actor type the product did not yet know about was visible to
  # every member of the account, unfiltered by the ceiling and unfiltered by the capability. The first
  # notification about something that is NOT a tenant's conversation -- an internal record, an operational
  # signal, a platform support case -- would have been published to tenants on the day it was created, by a
  # default nobody chose. An allow-list of one is worth having precisely because that default was wrong.
  #
  #   Conversation  Every notification this product creates. All six `NotificationBuilder.new` call sites pass
  #                 a Conversation (app/listeners/notification_listener.rb:7,21,42;
  #                 app/services/messages/new_message_notification_service.rb:20,36;
  #                 app/services/messages/mention_service.rb:55) and `Notification::PRIMARY_ACTORS` names only
  #                 this one (app/models/notification.rb:56). Authorized by the subselect below.
  #
  # TWO TYPES WERE CONSIDERED AND REFUSED, which is what makes this a decision rather than a shrug:
  #
  #   Message       HISTORICAL. `Message` still declares `has_many :notifications, as: :primary_actor`
  #                 (app/models/message.rb:136) and `Migration::RemoveMessageNotifications` exists to delete
  #                 the rows (app/jobs/migration/remove_message_notifications.rb:6), so a row could survive a
  #                 lost enqueue. Such a row IS about a conversation -- the message's own -- but the
  #                 notifications row does not say WHICH, so it cannot be authorized. Refused rather than
  #                 shown, and it costs nothing: the feed cannot render one anyway
  #                 (`Notification#push_message_title` calls `display_id` on the primary actor and `Message`
  #                 has no such method, so the index already raises on one today).
  #
  #   sla_missed_*  The three enum values (app/models/notification.rb:44-46) are declared and have no creation
  #                 site anywhere in app/, custom/ or lib/. Nothing to authorize, so nothing is allowed.
  #
  #   PlatformSupport::Ticket
  #                 A Lynomia support ticket raised BY a tenant, about Lynomia. One notification type only --
  #                 `platform_support_reply`, an operator's public reply -- and never an internal note
  #                 (docs/platform-support/12-refresh-against-product-refinement.md §5). It is NOT
  #                 conversation-scoped, so it does not share the conversation subselect: it has its own
  #                 branch in `narrow` and its own branch in `permits?`, authorized by
  #                 `PlatformSupport::TicketPolicy`, whose Scope supplies the account predicate itself and
  #                 then narrows by role (an administrator sees their account's tickets, an agent sees only
  #                 the ones they reported).
  #
  # ADDING A TYPE IS A DELIBERATE ACT with its own rule, taken here, and a LONGER LIST ALONE IS A DEFECT.
  # `narrow` used to apply the conversation subselect to the whole allowed set, so a ticket id would have been
  # compared against conversation ids -- not a refusal but a silent WRONG ANSWER by id collision, in both
  # directions: a ticket notification shown because some conversation happens to share its id, and hidden when
  # none does. That is why every type named here now has its own condition in both methods, and why `narrow`
  # ends in an explicit `else` that excludes.
  # `spec/services/notifications/conversation_visibility_spec.rb` fails if this list and
  # `Notification::PRIMARY_ACTORS` drift apart, so a type added for any other reason cannot widen visibility
  # silently.
  VISIBLE_ACTOR_TYPES = [CONVERSATION_ACTOR, PLATFORM_SUPPORT_TICKET_ACTOR].freeze

  def self.for(account:, user:)
    new(account: account, user: user)
  end

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # True only when BOTH layers impose nothing, which in practice means an administrator (or an agent bot).
  #
  # It says nothing about the ALLOW-LIST, which applies to such a member too: "unrestricted" means unrestricted
  # with respect to which conversations they may reach, never authorized for a kind of notification nobody has
  # authorized them for.
  #
  # Note what is NOT unrestricted any more: a plain agent, and a holder of `conversation_manage`. The
  # capability layer says nothing about either, but the ceiling does -- they see the conversations of their
  # inboxes and teams, and no others. Before the ceiling was composed in, such a member was handed the whole
  # account's notifications.
  def unrestricted?
    capability_scope.unrestricted? && access_ceiling.unrestricted?
  end

  # The relation, narrowed. One uncorrelated subselect per actor type; never a check per row.
  #
  # TYPE-DISPATCHED, AND THE DISPATCH IS THE POINT. Each allowed type contributes its own `(type, ids)` pair
  # and the pairs are OR-ed, so an id is only ever compared against ids of its own kind. A type that is not
  # named contributes nothing and is therefore excluded -- the same fail-closed answer the allow-list gives,
  # arrived at structurally rather than by a second filter.
  #
  # Both halves are `relation.where(...)` over the same relation, which is what `Relation#or` requires, and
  # `index ["primary_actor_type", "primary_actor_id"]` already exists on this table.
  def narrow(relation)
    conversation_rows(relation).or(platform_support_ticket_rows(relation))
  end

  # The same question about one notification, so that an id is not a way around the relation.
  #
  # This asks the POLICY, not the two layers separately. `ConversationPolicy#show?` already composes them --
  # the administrator and agent-bot short-circuits, then `Conversations::AccessCeiling` through the delegation
  # in `Custom::ConversationPolicy`, then `Conversations::CapabilityScope` -- and it is what every other
  # conversation record read in the product is authorized by. Asking it means the notification record path is
  # the canonical answer rather than a copy of it, and it stays correct if either layer changes.
  # The same question about one notification, in the order the implementation contract fixes (§5.3): the actor
  # type is on the allow-list, the row belongs to this account, then the type's own rule.
  def permits?(notification)
    return false unless VISIBLE_ACTOR_TYPES.include?(notification.primary_actor_type)
    # The account this object was built for. NOT a redundant guard on top of the callers' scoping: without it
    # this method's own answer is wrong for an input it accepts, because `ConversationPolicy#show?`
    # short-circuits to true for an administrator and does not care which account the conversation belongs to.
    # So an administrator of one account asked about another account's notification would be told yes. Every
    # caller happens to scope by account today -- the controller's `fetch_notification` reads
    # `current_user.notifications.where(account_id: Current.account.id)`
    # (app/controllers/api/v1/accounts/notifications_controller.rb:72), the listener takes the account from the
    # notification itself -- so this changes no reachable behaviour. It makes the object correct on its own
    # terms, which is what an authorization answer has to be.
    return false unless notification.account_id == @account.id

    # One branch per allowed type, and an `else` that refuses. A type reaching here with no branch would be a
    # type on the allow-list with no rule, which is the one combination this object must never answer yes to.
    case notification.primary_actor_type
    when CONVERSATION_ACTOR then permits_conversation?(notification)
    when PLATFORM_SUPPORT_TICKET_ACTOR then permits_platform_support_ticket?(notification)
    else false
    end
  end

  private

  def permits_conversation?(notification)
    conversation = notification.primary_actor
    return false if conversation.blank?

    ::ConversationPolicy.new(
      { user: @user, account: @account, account_user: account_user }, conversation
    ).show?
  end

  # The ticket must exist, belong to THIS account, and have a non-nil `account_id`.
  #
  # The non-nil part is not pedantry: `platform_support_tickets.account_id` is nullable and goes NULL when the
  # subject account is deleted, keeping `account_name_at_creation` for Lynomia's own history. A nil there must
  # never compare equal to anything, and an orphaned ticket must stop being readable by any tenant -- which is
  # exactly what the policy scope's `where(account_id: account.id)` already answers, asserted here as well so
  # the record path cannot drift from the relation path.
  def permits_platform_support_ticket?(notification)
    ticket = notification.primary_actor
    return false if ticket.blank?
    return false if ticket.account_id.nil? || ticket.account_id != @account.id

    ::PlatformSupport::TicketPolicy.new(
      { user: @user, account: @account, account_user: account_user }, ticket
    ).show?
  end

  # The conversation half, unchanged: the allow-list pins the type, and the subselect is added only for a
  # member who is restricted.
  def conversation_rows(relation)
    rows = relation.where(primary_actor_type: CONVERSATION_ACTOR)
    return rows if unrestricted?

    rows.where(primary_actor_id: authorized_conversation_ids)
  end

  # The ticket half. `unrestricted?` is DELIBERATELY NOT CONSULTED: it answers a question about which
  # conversations a member may reach, and being unrestricted there says nothing about which support tickets
  # they may read. Ticket visibility is only ever the Platform Support policy scope, for every member
  # including an administrator.
  def platform_support_ticket_rows(relation)
    relation.where(
      primary_actor_type: PLATFORM_SUPPORT_TICKET_ACTOR,
      primary_actor_id: authorized_platform_support_ticket_ids
    )
  end

  # A relation, not an array, for the same reason as the conversation subselect: Rails renders it as
  # `IN (SELECT "platform_support_tickets"."id" ...)`, so the answer is not bounded by how many tickets the
  # member can reach. The Scope applies the account predicate itself, so the unscoped relation is what it
  # expects (§3).
  def authorized_platform_support_ticket_ids
    ::PlatformSupport::TicketPolicy::Scope.new(
      { user: @user, account: @account, account_user: account_user }, ::PlatformSupport::Ticket.all
    ).resolve.select(:id)
  end

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
