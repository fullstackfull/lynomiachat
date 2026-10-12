# The SOCKET half of read-time conversation authorization on the notification feed.
#
# WHAT THIS CLOSES, and why the other two halves do not reach it. The notification payload pushed over
# ActionCable is `notification.push_event_data` (app/listeners/action_cable_listener.rb:7 and :13), which
# merges `primary_actor_data` -- the conversation's full push payload plus `push_message_body` twice
# (app/models/notification.rb:201-208). That is the same content the feed exposes, delivered without a request.
#
# `notification.created` is already safe before this: `NotificationBuilder` only writes a row when
# `ConversationPolicy#show?` allows it (app/builders/notification_builder.rb:31,42-53), so a row cannot be
# born unauthorized. `notification.updated` is NOT safe, because it fires from
# `after_update_commit :dispatch_update_event` (app/models/notification.rb:54) for every writer of the row,
# and one of those writers has no user context and no authorization at all:
#
#   Notification::ReopenSnoozedNotificationsJob (app/jobs/notification/reopen_snoozed_notifications_job.rb:17)
#     A cron. It unsnoozes every notification whose snooze has expired and calls `update!`, which re-pushes the
#     whole conversation payload to the recipient -- whatever their access is NOW. This is the one path by
#     which a member narrowed after the notification was snoozed would still be handed the content.
#
#   Notification::MarkConversationReadService (app/services/notification/mark_conversation_read_service.rb:8)
#     Incidentally safe, because its only caller is inside an action already gated by
#     `authorize @conversation, :show?` (app/controllers/api/v1/accounts/conversations_controller.rb:117,190).
#     Gated here anyway: relying on a caller's authorization is how the gap being closed came about.
#
# BOTH EVENTS ARE GATED, not just the unsafe one. A rule applied to one of two symmetrical events is a rule
# the next reader will get wrong, and the created path costs one `permits?` on a record already in memory.
#
# `notification.deleted` is deliberately NOT gated. Its payload is `{ id: }` only (:25-29) -- no conversation,
# no content -- and its counts come from `NotificationFinder`, which is already narrowed. Suppressing it would
# leave a hidden-then-deleted notification stuck in the browser's local store instead.
module Custom::ActionCableListener
  def notification_created(event)
    return unless notification_conversation_readable?(event)

    super
  end

  def notification_updated(event)
    return unless notification_conversation_readable?(event)

    super
  end

  private

  # The recipient is the notification's own user, not `Current.user`: this runs from a cron as well as from a
  # request, and on the cron path there is no current user at all.
  def notification_conversation_readable?(event)
    notification = event.data[:notification]
    return true if notification.blank?

    user = notification.user
    account = notification.account
    return true if user.blank? || account.blank?

    ::Notifications::ConversationVisibility.for(account: account, user: user).permits?(notification)
  end
end
