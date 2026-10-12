# READ-TIME CONVERSATION AUTHORIZATION FOR THE NOTIFICATION FEED -- the relation half.
#
# THE GAP THIS CLOSES. `NotificationBuilder` already refuses to CREATE a notification the recipient cannot
# reach: `build_notification` returns early unless `user_can_access_conversation?`
# (app/builders/notification_builder.rb:31 and :42-53), which asks `ConversationPolicy#show?` (:49) and so
# carries D1's capability narrowing. But that is a check at WRITE time, and access moves afterwards -- an
# administrator edits a permission set, the `custom_roles` entitlement lapses or returns, a conversation is
# reassigned. Nothing revisits the rows already written: the only cleanup anywhere is
# `has_many :notifications, as: :primary_actor, dependent: :destroy_async`
# (app/models/conversation.rb:131), and that fires on destroying the CONVERSATION, never on a change of access.
#
# So before this, a member narrowed to `conversation_participating_manage` kept a feed over everyone else's
# conversations -- and the feed is not metadata. `index.json.jbuilder` emits `push_message_body` (:13, the
# message text), `primary_actor.push_event_data` (:17, which carries the last chat message in full and the
# contact's name, email and phone through `Conversations::EventDataPresenter#push_data` and `#push_meta`) and
# `secondary_actor.push_event_data` (:20, a Message, serialized from `attributes.symbolize_keys`
# (app/models/message.rb:148), so the whole body again).
#
# AND access also moves for a reason that has nothing to do with capabilities: an inbox membership is removed, a
# team membership is removed, or a conversation's `team_id` changes. `InboxMember` and `TeamMember` invalidate
# one count cache on create/destroy and do nothing else (app/models/inbox_member.rb:27,39-41;
# app/models/team_member.rb:22,26-28), so those rows went unrevisited too.
#
# THE RULE IS NOT RESTATED HERE, OR ANYWHERE BUT ONE PLACE. `Notifications::ConversationVisibility` translates
# the rule onto this table; the rule itself is the INTERSECTION of two existing objects, neither of which lives
# here -- the Inbox/Team/account ceiling (`Conversations::AccessCeiling`, which `ConversationPolicy` itself
# delegates to) AND the capability scope (`Conversations::CapabilityScope`). Grandfathering, widest-wins, the
# administrator short-circuit, D2's entitlement bound and the inbox-or-team semantics are therefore whatever
# those two say they are, today and after any future change to them.
#
# WHY THIS METHOD. `find_all_notifications` (app/finders/notification_finder.rb:39) is the one place every
# answer this finder gives derives from: `notifications`, `unread_count` and `count` all read `@notifications`
# (:13-31). The page and the two counts therefore cannot disagree -- they are the same relation. And the
# finder is not only the API's: `BaseListener#extract_notification_and_account`
# (app/listeners/base_listener.rb:9-15) builds one to compute the counts pushed over ActionCable on every
# notification.created / .updated / .deleted, so the websocket badge narrows with the feed rather than
# contradicting it.
module Custom::NotificationFinder
  private

  # Private, as it is on the class this is prepended to (app/finders/notification_finder.rb:31 and :39): a
  # prepended module carries its own visibility, and making a finder internal public is not part of this change.
  def find_all_notifications
    super
    @notifications = conversation_visibility.narrow(@notifications)
  end

  def conversation_visibility
    @conversation_visibility ||= ::Notifications::ConversationVisibility.for(account: current_account, user: current_user)
  end
end
