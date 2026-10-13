# Writes the ONE Platform Support notification row that exists: `platform_support_reply`, once per operator
# PUBLIC reply, per eligible recipient (docs/platform-support/12-refresh-against-product-refinement.md §5).
#
# NOTHING ELSE GETS A ROW. Not a ticket's creation, not an assignment, not a priority or category change, not
# any `sla_*` event, not a move to `waiting_on_lynomia`, and -- the one that would be a disclosure rather than
# noise -- NEVER an internal note. That is enforced by this being the only writer: there is no generic
# "notify" entry point here that a later caller could reach with a different trigger.
#
# WHY `NotificationBuilder` IS NOT USED. It is conversation-shaped and would raise: `build_notification` calls
# `primary_actor.contact.blocked?` (app/builders/notification_builder.rb:29) and its access check resolves a
# conversation (:42-53). A ticket has neither a contact nor a conversation.
#
# `secondary_actor` IS DELIBERATELY NIL. The feed serializer emits `secondary_actor.push_event_data`
# (app/views/api/v1/accounts/notifications/index.json.jbuilder:20), and `NotificationBuilder` defaults it to
# `Current.user` -- which on this path is the acting Lynomia OPERATOR. Every operator message a customer reads
# is authored by "Lynomia Support" and the individual's name is never serialized (§2); defaulting the
# secondary actor would have published it through the bell instead.
#
# AUTHORIZED AT WRITE TIME TOO, not only at read time. `Notifications::ConversationVisibility#permits?` is the
# authority and it is asked again on every read, so a row written for somebody who should not see it would be
# hidden rather than shown. It is still not written: a row nobody may read is a row that will be miscounted
# (the badge counts rows the server can see) and puzzled over later. The question asked is
# `PlatformSupport::TicketPolicy#show?`, the same one the read path asks.
#
# RECIPIENTS: the reporter, plus the account's administrators. That is the customer-side audience D-1 defines
# -- an administrator sees every ticket of their account, an agent sees only the ones they reported -- so the
# set is exactly "the members who can open this ticket", computed rather than assumed. A reporter who is also
# an administrator gets one row, not two.
#
# NO DUPLICATE STORM. `Notification::RemoveDuplicateNotificationJob` is enqueued for every row created and now
# keys on `(account_id, user_id, primary_actor_type, primary_actor_id)`, so a second reply on the same ticket
# leaves that recipient with one row, the newest.
class PlatformSupport::Notifications::ReplyNotifier
  NOTIFICATION_TYPE = 'platform_support_reply'.freeze

  def initialize(ticket:)
    @ticket = ticket
  end

  def perform
    account = @ticket.account
    # An orphaned ticket (its subject account was deleted, `account_id` NULL) has no tenant audience at all,
    # and the policy scope would refuse every reader anyway.
    return [] if account.nil?

    recipients(account).map { |user| create_row(account, user) }
  end

  private

  def recipients(account)
    candidates = [@ticket.reporter, *account.administrators].compact.uniq
    return [] if candidates.empty?

    # One membership query for the whole set rather than one per candidate: an account's administrator list is
    # unbounded and this runs inside the request that saved the reply.
    memberships = account.account_users.where(user_id: candidates.map(&:id)).index_by(&:user_id)

    candidates.select { |user| permitted?(account, user, memberships[user.id]) }
  end

  def permitted?(account, user, account_user)
    return false if account_user.nil?

    ::PlatformSupport::TicketPolicy.new(
      { user: user, account: account, account_user: account_user }, @ticket
    ).show?
  end

  def create_row(account, user)
    user.notifications.create!(
      notification_type: NOTIFICATION_TYPE,
      account: account,
      primary_actor: @ticket,
      secondary_actor: nil
    )
  end
end
