# The RECORD half of read-time conversation authorization on the notification feed.
#
# WHY A SECOND HALF IS NEEDED. `Custom::NotificationFinder` narrows the feed, the two counts and the ActionCable
# badge, but the member routes do not go through the finder at all: `fetch_notification`
# (app/controllers/api/v1/accounts/notifications_controller.rb:71-73) looks a row up by id straight off
# `current_user.notifications`. Four actions hang off that one `before_action` (:5) -- `update`, `destroy`,
# `snooze` and `unread` -- so without this, narrowing the list would leave every one of them answerable by
# anyone who knows or guesses an id, and notification ids are sequential bigints.
#
# WHAT THOSE ROUTES DISCLOSE, measured rather than assumed. `Notification` declares no `as_json` or
# `serializable_hash` override, there is no `app/serializers/` and no ActiveModelSerializers in the bundle, so
# `render json: @notification` emits the table columns and nothing else -- verified by serializing a real
# record: no message body, no contact name, no `primary_actor` payload. The exposure through these four routes
# is therefore metadata (that a notification exists, its type, and the conversation's internal id), not
# content.
#
# The CONTENT on these routes is one step further out. `update`, `snooze` and `unread` call
# `@notification.update`, which fires `after_update_commit :dispatch_update_event`
# (app/models/notification.rb:54) and broadcasts the FULL `push_event_data` -- message text and contact details
# included -- to that user's socket (app/listeners/action_cable_listener.rb:10-14). Refusing the action closes
# that too; `Custom::ActionCableListener` closes the writers that are not requests at all.
#
# THE SAME ANSWER AS THE LIST, BY CONSTRUCTION. Both halves ask `Notifications::ConversationVisibility`, which
# asks `Conversations::CapabilityScope`. A notification the feed omits is one this refuses, and
# spec/requests/notification_conversation_authorization_spec.rb asserts that agreement for every mode rather
# than trusting it.
#
# 404, NOT 403. `ActiveRecord::RecordNotFound` is what an unknown id already produces here, and it is what the
# custom-roles endpoint chose for the same reason (custom/app/controllers/api/v1/accounts/custom_roles_controller.rb:7-8):
# a 403 would confirm that the id exists and belongs to this user. The response is byte-identical whether the
# id is wrong, somebody else's, or real-but-unauthorized -- asserted.
module Custom::Api::V1::Accounts::NotificationsController
  private

  # Private, as it is on the class this is prepended to (notifications_controller.rb:62 and :71). A prepended
  # module carries its own visibility, and a PUBLIC instance method on a controller is a routable action --
  # making this one public would add `fetch_notification` to the controller's action surface.
  def fetch_notification
    super
    return if conversation_visibility.permits?(@notification)

    raise ActiveRecord::RecordNotFound
  end

  def conversation_visibility
    @conversation_visibility ||= ::Notifications::ConversationVisibility.for(account: Current.account, user: Current.user)
  end
end
