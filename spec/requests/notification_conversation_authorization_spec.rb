require 'rails_helper'

# READ-TIME CONVERSATION AUTHORIZATION ON THE NOTIFICATION FEED.
#
# The gap: NotificationBuilder refuses to CREATE a notification the recipient cannot reach, but access moves
# afterwards and nothing revisits the rows already written. Every example here therefore creates the
# notification rows DIRECTLY rather than through the builder -- that is the whole point. They stand for rows
# written when the member's access was wider.
#
# The content at stake is not metadata. index.json.jbuilder emits push_message_body, primary_actor (whose
# push_data carries the last chat message and the contact's name, email and phone) and secondary_actor (a
# Message, serialized from its own attributes). The leak assertions below read the RAW response body, so they
# hold however those three fields are composed.
RSpec.describe 'Notification feed conversation authorization', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:membership) { account.account_users.find_by(user: agent) }
  let(:contact) { create(:contact, account: account, name: 'Trillian Astra') }

  let(:mine) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:unassigned) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: nil) }
  let(:theirs) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: other_agent) }

  # The secret only ever lives in the conversation the holder must not reach.
  let!(:secret_message) do
    create(:message, account: account, inbox: inbox, conversation: theirs, content: 'NUTRIMATIC-DRINKS-DISPENSER')
  end

  let!(:mine_notification) { notification_for(mine) }
  let!(:unassigned_notification) { notification_for(unassigned) }
  let!(:theirs_notification) { notification_for(theirs, secondary: secret_message) }

  before do
    account.enable_features!('custom_roles')
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_member, inbox: inbox, user: other_agent)
  end

  def notification_for(conversation, secondary: nil)
    agent.notifications.create!(account: account, primary_actor: conversation,
                                notification_type: secondary ? 'conversation_mention' : 'conversation_assignment',
                                secondary_actor: secondary)
  end

  def attach(*permissions)
    membership.update!(custom_role: create(:custom_role, account: account, permissions: permissions), role: :agent)
  end

  def feed
    get "/api/v1/accounts/#{account.id}/notifications", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['data']
  end

  def listed_ids
    feed['payload'].pluck('id')
  end

  describe 'conversation_manage, which must change nothing' do
    it 'returns every notification, as before' do
      attach('conversation_manage')

      expect(listed_ids).to contain_exactly(mine_notification.id, unassigned_notification.id, theirs_notification.id)
    end
  end

  describe 'an administrator and a plain agent, whose reach this never touches' do
    it 'leaves a membership with no set attached alone' do
      expect(listed_ids).to contain_exactly(mine_notification.id, unassigned_notification.id, theirs_notification.id)
    end

    it 'leaves an administrator alone' do
      admin = create(:user, account: account, role: :administrator)
      admin.notifications.create!(account: account, primary_actor: theirs, notification_type: 'conversation_assignment')

      get "/api/v1/accounts/#{account.id}/notifications", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['data']['payload'].length).to eq(1)
    end
  end

  describe 'conversation_participating_manage -> only their own' do
    before { attach('conversation_participating_manage') }

    it 'hides the notification for a conversation assigned to somebody else' do
      expect(listed_ids).to contain_exactly(mine_notification.id)
    end

    it 'hides the notification for an unassigned conversation' do
      expect(listed_ids).not_to include(unassigned_notification.id)
    end
  end

  describe 'conversation_unassigned_manage -> their own and the unassigned' do
    before { attach('conversation_unassigned_manage') }

    it 'matches the capability semantics exactly' do
      expect(listed_ids).to contain_exactly(mine_notification.id, unassigned_notification.id)
    end
  end

  describe 'an enforced set naming none of the three -> no conversation notification at all' do
    before { attach('contact_manage') }

    it 'returns an empty feed' do
      expect(listed_ids).to be_empty
    end

    it 'reports zero in both counts' do
      expect(feed['meta']).to include('count' => 0, 'unread_count' => 0)
    end
  end

  describe 'a grandfathered set, which must keep what it had' do
    it 'returns everything, matching the D1 grandfather rule' do
      attach('contact_manage')
      membership.custom_role.update_column(:conversation_scope_enforced, false) # rubocop:disable Rails/SkipsModelValidations

      expect(listed_ids).to contain_exactly(mine_notification.id, unassigned_notification.id, theirs_notification.id)
    end
  end

  describe 'content, which is what the feed actually exposes' do
    before { attach('conversation_participating_manage') }

    it 'does not leak the message body of an inaccessible conversation' do
      get "/api/v1/accounts/#{account.id}/notifications", headers: agent.create_new_auth_token, as: :json

      expect(response.body).not_to include('NUTRIMATIC-DRINKS-DISPENSER')
    end

    it 'does not leak push_event_data for an inaccessible conversation' do
      get "/api/v1/accounts/#{account.id}/notifications", headers: agent.create_new_auth_token, as: :json

      # Structural, not a substring search: a display_id is a small integer that occurs all over the payload
      # for innocent reasons, so the assertion is that no primary_actor in the feed IS that conversation.
      actors = response.parsed_body['data']['payload'].map { |n| n.dig('primary_actor', 'id') }
      expect(actors).to contain_exactly(mine.display_id)
      expect(actors).not_to include(theirs.display_id)
    end

    # The contact is shared by all three conversations, so its name reaches the payload through the one
    # conversation the holder CAN read. The assertion that matters is that it does not arrive through the other.
    it 'exposes the contact only through the conversation the holder may read' do
      attach('contact_manage')

      get "/api/v1/accounts/#{account.id}/notifications", headers: agent.create_new_auth_token, as: :json

      expect(response.body).not_to include('Trillian Astra')
    end
  end

  describe 'the member routes, which do not go through the finder' do
    before { attach('conversation_participating_manage') }

    it 'refuses to mark an excluded notification read' do
      patch "/api/v1/accounts/#{account.id}/notifications/#{theirs_notification.id}",
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(theirs_notification.reload.read_at).to be_nil
    end

    it 'refuses to snooze one' do
      post "/api/v1/accounts/#{account.id}/notifications/#{theirs_notification.id}/snooze",
           params: { snoozed_until: 1.day.from_now.iso8601 }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(theirs_notification.reload.snoozed_until).to be_nil
    end

    it 'refuses to unread one' do
      post "/api/v1/accounts/#{account.id}/notifications/#{theirs_notification.id}/unread",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'refuses to destroy one, and the row survives' do
      delete "/api/v1/accounts/#{account.id}/notifications/#{theirs_notification.id}",
             headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Notification.exists?(theirs_notification.id)).to be(true)
    end

    it 'still allows the holder their own notification' do
      patch "/api/v1/accounts/#{account.id}/notifications/#{mine_notification.id}",
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(mine_notification.reload.read_at).to be_present
    end
  end

  # THE ADVERSARIAL CASE the decision asks for by name: an id is not a capability.
  describe 'knowing a notification id' do
    before { attach('conversation_participating_manage') }

    it 'answers exactly as it does for an id that does not exist, and discloses nothing' do
      patch "/api/v1/accounts/#{account.id}/notifications/#{theirs_notification.id}",
            headers: agent.create_new_auth_token, as: :json
      real_but_unauthorized = [response.status, response.body]

      patch "/api/v1/accounts/#{account.id}/notifications/#{Notification.maximum(:id) + 10_000}",
            headers: agent.create_new_auth_token, as: :json
      nonexistent = [response.status, response.body]

      expect(real_but_unauthorized).to eq(nonexistent)
      expect(real_but_unauthorized.last).not_to include('NUTRIMATIC-DRINKS-DISPENSER')
      expect(real_but_unauthorized.last).not_to include(theirs.display_id.to_s)
    end

    it 'does not let another user id be fetched either' do
      foreign = other_agent.notifications.create!(account: account, primary_actor: mine,
                                                  notification_type: 'conversation_assignment')

      patch "/api/v1/accounts/#{account.id}/notifications/#{foreign.id}",
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  # The list and the record are two expressions of one rule, so they must never disagree. Asserted rather than
  # assumed, for every mode.
  #
  # The probe is POST snooze with NO snoozed_until, which is the one member route that reads without writing
  # (notifications_controller.rb:55-59 updates only `if params[:snoozed_until]`). A mutating probe would mark
  # the notification read, and the feed hides read notifications for an unrelated reason -- which would make
  # this compare two different sets and pass or fail by accident.
  describe 'the list and the record agreeing' do
    it 'refuses exactly the notifications the feed omits, in every mode' do
      [%w[conversation_manage], %w[conversation_unassigned_manage], %w[conversation_participating_manage],
       %w[contact_manage]].each do |permissions|
        attach(*permissions)
        listed = listed_ids

        [mine_notification, unassigned_notification, theirs_notification].each do |notification|
          post "/api/v1/accounts/#{account.id}/notifications/#{notification.id}/snooze",
               headers: agent.create_new_auth_token, as: :json

          expected = listed.include?(notification.id) ? 200 : 404
          expect(response.status).to eq(expected),
                                     "#{permissions.first}: notification #{notification.id} listed=#{listed.include?(notification.id)} " \
                                     "but the record probe returned #{response.status}"
        end
      end
    end
  end

  describe 'permission removed and restored, with no row touched' do
    it 'hides a notification when the capability narrows and shows it again when it widens' do
      attach('conversation_manage')
      expect(listed_ids).to include(theirs_notification.id)

      membership.custom_role.update!(permissions: %w[conversation_participating_manage])
      expect(listed_ids).not_to include(theirs_notification.id)

      # Still there. Nothing was purged, which is what makes the next line possible.
      expect(Notification.exists?(theirs_notification.id)).to be(true)

      membership.custom_role.update!(permissions: %w[conversation_manage])
      expect(listed_ids).to include(theirs_notification.id)
    end

    it 'does the same when the account entitlement lapses and returns (DECISION 2)' do
      attach('conversation_participating_manage')
      expect(listed_ids).to contain_exactly(mine_notification.id)

      account.disable_features!('custom_roles')
      expect(listed_ids).to contain_exactly(mine_notification.id, unassigned_notification.id, theirs_notification.id)

      account.enable_features!('custom_roles')
      expect(listed_ids).to contain_exactly(mine_notification.id)
    end
  end

  describe 'counts and pagination staying coherent' do
    it 'counts what it returns' do
      attach('conversation_unassigned_manage')
      data = feed

      expect(data['meta']['count']).to eq(data['payload'].length)
      expect(data['meta']['unread_count']).to eq(2)
    end

    it 'pages the narrowed set rather than a wider one' do
      attach('conversation_participating_manage')
      20.times { notification_for(theirs) }
      18.times { notification_for(mine) }

      data = feed

      # 19 of their own: the original plus 18. One page of 15, and a count that describes the narrowed set.
      expect(data['meta']['count']).to eq(19)
      expect(data['payload'].length).to eq(15)
      expect(data['payload'].pluck('id')).not_to include(theirs_notification.id)
    end

    it 'narrows the unread_count endpoint too' do
      attach('conversation_participating_manage')

      get "/api/v1/accounts/#{account.id}/notifications/unread_count", headers: agent.create_new_auth_token, as: :json

      expect(response.body.to_i).to eq(1)
    end
  end

  describe 'bulk delete, which must not destroy what it cannot show' do
    before { attach('conversation_participating_manage') }

    it 'leaves the hidden rows intact when the member deletes everything' do
      perform_enqueued_jobs do
        post "/api/v1/accounts/#{account.id}/notifications/destroy_all", headers: agent.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:success)
      expect(Notification.exists?(mine_notification.id)).to be(false)
      # The two it could not see survive, which is what keeps "permission restored -> visible again" true.
      expect(Notification.exists?(unassigned_notification.id)).to be(true)
      expect(Notification.exists?(theirs_notification.id)).to be(true)
    end

    it 'still deletes everything for a member who can see everything' do
      attach('conversation_manage')

      perform_enqueued_jobs do
        post "/api/v1/accounts/#{account.id}/notifications/destroy_all", headers: agent.create_new_auth_token, as: :json
      end

      expect(Notification.where(user: agent, account: account).count).to eq(0)
    end

    it 'restores the hidden rows to the feed when the capability widens again' do
      perform_enqueued_jobs do
        post "/api/v1/accounts/#{account.id}/notifications/destroy_all", headers: agent.create_new_auth_token, as: :json
      end
      attach('conversation_manage')

      expect(listed_ids).to contain_exactly(unassigned_notification.id, theirs_notification.id)
    end
  end

  # The payload the browser receives without asking. Gated for the same reason the feed is: it carries
  # push_event_data, and one of its writers is a cron with no user context.
  describe 'the ActionCable payload' do
    it 'is not pushed for a conversation the recipient may no longer read' do
      attach('conversation_participating_manage')

      expect(ActionCableBroadcastJob).not_to receive(:perform_later)

      Rails.configuration.dispatcher.dispatch(Events::Types::NOTIFICATION_UPDATED, Time.zone.now,
                                              notification: theirs_notification.reload)
    end

    it 'is still pushed for one they can read' do
      attach('conversation_participating_manage')

      expect(ActionCableBroadcastJob).to receive(:perform_later).once

      Rails.configuration.dispatcher.dispatch(Events::Types::NOTIFICATION_UPDATED, Time.zone.now,
                                              notification: mine_notification.reload)
    end

    it 'is pushed as before when nothing is narrowed' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).once

      Rails.configuration.dispatcher.dispatch(Events::Types::NOTIFICATION_UPDATED, Time.zone.now,
                                              notification: theirs_notification.reload)
    end
  end

  describe 'tenant isolation' do
    it 'reaches nothing in another account, whatever the capability' do
      other = create(:account)
      other_inbox = create(:inbox, account: other)
      foreign_conversation = create(:conversation, account: other, inbox: other_inbox,
                                                   contact: create(:contact, account: other), assignee: nil)
      create(:account_user, account: other, user: agent, role: :agent)
      foreign_notification = agent.notifications.create!(account: other, primary_actor: foreign_conversation,
                                                         notification_type: 'conversation_assignment')
      attach('conversation_unassigned_manage')

      expect(listed_ids).not_to include(foreign_notification.id)

      patch "/api/v1/accounts/#{account.id}/notifications/#{foreign_notification.id}",
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
