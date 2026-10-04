# A contact bulk action, and then one message back to whoever asked for it.
#
# The endpoint answers `head :ok` as soon as this is queued, so the page that asked had no way to know when the
# work was actually done and refetched immediately — which, with Sidekiq, reads the list before the labels are
# written. The `contact.updated` pushes each contact produces correct a row's attributes but never its membership
# of a filtered list, so they cannot stand in for this (docs/contacts/10-phase-d.md).
#
# Broadcast the way `Account::BrandingEnrichmentJob` already does it: `ActionCableBroadcastJob` straight to the
# initiating user's own `pubsub_token`, with no dispatcher event and no listener — so it reaches the person who
# pressed the button and nobody else's tabs.
class Contacts::BulkActionJob < ApplicationJob
  queue_as :medium
  COMPLETED_EVENT = 'contact.bulk_action_completed'.freeze

  def perform(account_id, user_id, params)
    account = Account.find(account_id)
    user = User.find(user_id)

    # Set for the same reason BulkActionsJob sets it: every contact written here dispatches `contact.updated`,
    # and `ActionCableListener#broadcast` reads `Current.user` to name the performer. Without it a bulk write
    # looked like it came from nobody.
    Current.user = user

    Contacts::BulkActionService.new(
      account: account,
      user: user,
      params: params
    ).perform

    ActionCableBroadcastJob.perform_later([user.pubsub_token], COMPLETED_EVENT, { account_id: account.id })
  ensure
    Current.reset
  end
end
