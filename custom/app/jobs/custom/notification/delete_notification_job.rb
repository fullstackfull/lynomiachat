# "Delete all notifications" must not destroy what it is not allowed to show.
#
# THE CONFLICT THIS RESOLVES. `POST /notifications/destroy_all` enqueues this job, which destroys every
# notification row the user has in the account (app/jobs/notification/delete_notification_job.rb:5,9,11). Once
# the feed is narrowed, a member can no longer SEE the notifications for conversations outside their
# capability -- but that button would still destroy them, permanently and with no audit. That breaks the two
# properties the decision states outright: history is not deleted, and access restored means visible again.
# A row destroyed while hidden can never come back.
#
# So the job destroys exactly the set the feed would have shown, using the same single definition the feed
# uses. Rows the member cannot see are left untouched, which is the conservative direction and the one that
# keeps "permission restored -> visible again" true.
#
# `read` and `all` are both narrowed, because `super` applies the read filter to whatever relation it starts
# from and the authorization question is the same either way.
#
# NOT narrowed, and deliberately: nothing here looks at snoozed state. This job's set is "my notifications in
# this account", not the feed's default page, and changing that would be a change to retention rather than to
# authorization.
module Custom::Notification::DeleteNotificationJob
  def perform(user, account, type: :all)
    visibility = ::Notifications::ConversationVisibility.for(account: account, user: user)
    return super if visibility.unrestricted?

    deletable = visibility.narrow(user.notifications.where(account_id: account.id))

    ActiveRecord::Base.transaction do
      scope = type == :read ? deletable.where.not(read_at: nil) : deletable
      scope.destroy_all if [:all, :read].include?(type)
    end
  end
end
