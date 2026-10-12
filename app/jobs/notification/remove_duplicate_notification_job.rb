# Keeps one notification per recipient per thing-notified-about, by destroying the older rows.
#
# THE KEY IS `(account_id, user_id, primary_actor_type, primary_actor_id)`, and the two columns that used to be
# missing from it are the point of this file.
#
# `primary_actor_type` was ignored, which was harmless only while `Notification::PRIMARY_ACTORS` named exactly
# one type. It no longer does. `primary_actor_id` is an id WITHIN a type, never a global one, so a Platform
# Support ticket and a conversation can share it -- and nothing prevents that: the `notifications` table has
# no foreign keys at all, and `uniq_primary_actor_per_account_notifications` is NOT a unique index despite its
# name. This job is enqueued for every row created (`Notification#process_notification_delivery`), so with the
# type ignored the first operator reply on ticket 42 would have destroyed that recipient's notification about
# conversation 42 -- silent data loss across two unrelated features, caused by an id collision.
#
# `account_id` was ignored too. A user who belongs to two accounts holds notifications in both, and every
# other reader of this table is account-scoped (`NotificationFinder#find_all_notifications`,
# `Api::V1::Accounts::NotificationsController#fetch_notification`,
# `Notifications::ConversationVisibility#permits?`). Keyed without it, a row created in one account could
# destroy that user's row in another.
#
# `notification_type` is deliberately NOT part of the key. The behaviour this job exists for is "one row per
# recipient per thread, whatever kind of activity happened on it most recently"; narrowing by type would leave
# a stale assignment row sitting beside a fresh new-message row.
class Notification::RemoveDuplicateNotificationJob < ApplicationJob
  queue_as :default

  def perform(notification)
    return unless notification.is_a?(Notification)

    # Find older notifications about the same actor, for the same recipient, in the same account
    duplicate_notifications = Notification.where(
      account_id: notification.account_id,
      user_id: notification.user_id,
      primary_actor_type: notification.primary_actor_type,
      primary_actor_id: notification.primary_actor_id
    ).order(created_at: :desc)

    # Skip the first one (the latest notification) and destroy the rest
    duplicate_notifications.offset(1).each(&:destroy)
  end
end
