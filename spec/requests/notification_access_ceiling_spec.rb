require 'rails_helper'

# THE INBOX/TEAM ACCESS CEILING ON THE NOTIFICATION FEED, over HTTP.
#
# The companion file, spec/requests/notification_conversation_authorization_spec.rb, covers the capability
# layer. This one covers the ceiling and the intersection of the two, because they are independent
# restrictions and a notification is visible only if BOTH permit.
#
# Every member here is an ordinary agent holding NO permission set unless an example attaches one, which keeps
# Conversations::CapabilityScope at :base so the ceiling is the only thing acting. Notification rows are planted
# directly rather than through NotificationBuilder: they stand for rows written while the member still had
# access, which is the only way the gap can arise, since the builder checks the same policy at write time.
RSpec.describe 'Notification feed Inbox/Team access ceiling', type: :request do
  let(:account) { create(:account) }
  let(:mine_inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:membership) { account.account_users.find_by(user: agent) }
  let(:contact) { create(:contact, account: account) }

  # One conversation the member can reach by inbox, one they cannot reach at all.
  let(:reachable) { create(:conversation, account: account, inbox: mine_inbox, contact: contact, assignee: agent) }
  let(:elsewhere) { create(:conversation, account: account, inbox: other_inbox, contact: contact, assignee: agent) }

  let!(:elsewhere_secret) do
    create(:message, account: account, inbox: other_inbox, conversation: elsewhere, content: 'BISTROMATHIC-DRIVE')
  end

  let!(:reachable_notification) { plant(reachable) }
  let!(:elsewhere_notification) { plant(elsewhere, secondary: elsewhere_secret) }

  before { create(:inbox_member, inbox: mine_inbox, user: agent) }

  def plant(conversation, secondary: nil)
    agent.notifications.create!(account: account, primary_actor: conversation, secondary_actor: secondary,
                                notification_type: secondary ? 'conversation_mention' : 'conversation_assignment')
  end

  def attach(*permissions)
    account.enable_features!('custom_roles')
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

  def probe(notification)
    # POST snooze with no snoozed_until is the one member route that reads without writing
    # (notifications_controller.rb:56-60), so repeated probing cannot change what the feed returns.
    post "/api/v1/accounts/#{account.id}/notifications/#{notification.id}/snooze",
         headers: agent.create_new_auth_token, as: :json
    response.status
  end

  describe 'inbox membership' do
    it 'shows a notification for a conversation in an inbox the member belongs to' do
      expect(listed_ids).to include(reachable_notification.id)
    end

    it 'hides one in an inbox the member does not belong to, from the feed and both counts' do
      data = feed

      expect(data['payload'].pluck('id')).to contain_exactly(reachable_notification.id)
      expect(data['meta']['count']).to eq(1)
      expect(data['meta']['unread_count']).to eq(1)
    end

    it 'hides it from the unread_count endpoint too' do
      get "/api/v1/accounts/#{account.id}/notifications/unread_count", headers: agent.create_new_auth_token, as: :json

      expect(response.body.to_i).to eq(1)
    end

    it 'refuses it by id' do
      expect(probe(elsewhere_notification)).to eq(404)
    end

    it 'leaks neither the message body nor the conversation through the feed' do
      get "/api/v1/accounts/#{account.id}/notifications", headers: agent.create_new_auth_token, as: :json

      expect(response.body).not_to include('BISTROMATHIC-DRIVE')
      expect(response.parsed_body['data']['payload'].map { |n| n.dig('primary_actor', 'id') })
        .to contain_exactly(reachable.display_id)
    end

    it 'leaks neither through the refused member route' do
      probe(elsewhere_notification)

      expect(response.body).not_to include('BISTROMATHIC-DRIVE')
      expect(response.body).not_to include(elsewhere.display_id.to_s)
    end

    it 'does not push the socket payload for it' do
      expect(ActionCableBroadcastJob).not_to receive(:perform_later)

      Rails.configuration.dispatcher.dispatch(Events::Types::NOTIFICATION_UPDATED, Time.zone.now,
                                              notification: elsewhere_notification.reload)
    end

    it 'does push it once the member joins that inbox' do
      create(:inbox_member, inbox: other_inbox, user: agent)

      expect(ActionCableBroadcastJob).to receive(:perform_later).once

      Rails.configuration.dispatcher.dispatch(Events::Types::NOTIFICATION_UPDATED, Time.zone.now,
                                              notification: elsewhere_notification.reload)
    end

    it 'shows it the moment the member joins that inbox, from the same untouched row' do
      expect(listed_ids).not_to include(elsewhere_notification.id)

      create(:inbox_member, inbox: other_inbox, user: agent)

      expect(listed_ids).to include(elsewhere_notification.id)
      expect(elsewhere_notification.reload.read_at).to be_nil
    end

    it 'hides it again when the membership is removed, and keeps the row' do
      create(:inbox_member, inbox: other_inbox, user: agent)
      expect(listed_ids).to include(elsewhere_notification.id)

      InboxMember.find_by(inbox: other_inbox, user: agent).destroy!

      expect(listed_ids).not_to include(elsewhere_notification.id)
      expect(Notification.exists?(elsewhere_notification.id)).to be(true)
    end
  end

  # The canonical team semantics, preserved exactly: a team on the conversation plus membership of that team
  # grants access with no inbox membership at all, which is what ConversationPolicy#show? has always done.
  describe 'team membership' do
    it 'shows it on team membership alone, with no inbox membership' do
      elsewhere.update!(team: team)
      expect(listed_ids).not_to include(elsewhere_notification.id)

      create(:team_member, team: team, user: agent)

      expect(listed_ids).to include(elsewhere_notification.id)
      expect(probe(elsewhere_notification)).to eq(200)
    end

    it 'hides it again when team membership is removed' do
      elsewhere.update!(team: team)
      create(:team_member, team: team, user: agent)
      expect(listed_ids).to include(elsewhere_notification.id)

      TeamMember.find_by(team: team, user: agent).destroy!

      expect(listed_ids).not_to include(elsewhere_notification.id)
    end

    it 'does not grant on team membership when the conversation has no team' do
      create(:team_member, team: team, user: agent)

      expect(listed_ids).not_to include(elsewhere_notification.id)
    end

    it 'does not grant when the conversation carries a team the member is not in' do
      elsewhere.update!(team: create(:team, account: account))
      create(:team_member, team: team, user: agent)

      expect(listed_ids).not_to include(elsewhere_notification.id)
    end
  end

  describe 'an administrator, whose reach the ceiling never touches' do
    it 'sees a notification for any conversation in the account' do
      admin = create(:user, account: account, role: :administrator)
      admin.notifications.create!(account: account, primary_actor: elsewhere,
                                  notification_type: 'conversation_assignment')

      get "/api/v1/accounts/#{account.id}/notifications", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['data']['payload'].length).to eq(1)
    end
  end

  # BOTH LAYERS MUST PERMIT. Neither replaces the other, so each one-sided case denies.
  describe 'intersected with the conversation_* capability' do
    it 'shows it only when both permit' do
      create(:inbox_member, inbox: other_inbox, user: agent)
      attach('conversation_participating_manage')

      expect(listed_ids).to include(elsewhere_notification.id)
    end

    it 'denies when the capability permits but the ceiling does not' do
      # Assigned to the agent, so the capability says yes; not in that inbox and no team, so the ceiling says no.
      attach('conversation_participating_manage')

      expect(listed_ids).not_to include(elsewhere_notification.id)
      expect(probe(elsewhere_notification)).to eq(404)
    end

    it 'denies when the ceiling permits but the capability does not' do
      # In the member's inbox, so the ceiling says yes; assigned to somebody else, so the capability says no.
      create(:inbox_member, inbox: other_inbox, user: agent)
      elsewhere.update!(assignee: other_agent)
      attach('conversation_participating_manage')

      expect(listed_ids).not_to include(elsewhere_notification.id)
      expect(probe(elsewhere_notification)).to eq(404)
    end
  end

  describe 'the record and the feed agreeing' do
    it 'answers by id exactly as the feed does, for every notification' do
      listed = listed_ids

      [reachable_notification, elsewhere_notification].each do |notification|
        expect(probe(notification)).to eq(listed.include?(notification.id) ? 200 : 404),
                                       "notification #{notification.id}: listed=#{listed.include?(notification.id)}"
      end
    end

    it 'answers an unauthorized id exactly as it answers a nonexistent one' do
      probe(elsewhere_notification)
      unauthorized = [response.status, response.body]

      post "/api/v1/accounts/#{account.id}/notifications/#{Notification.maximum(:id) + 10_000}/snooze",
           headers: agent.create_new_auth_token, as: :json

      expect(unauthorized).to eq([response.status, response.body])
    end
  end

  describe 'counts and pagination after narrowing' do
    it 'pages and counts only what the ceiling allows' do
      20.times { plant(elsewhere) }
      18.times { plant(reachable) }

      data = feed

      expect(data['meta']['count']).to eq(19)
      expect(data['payload'].length).to eq(15)
      expect(data['payload'].pluck('id')).not_to include(elsewhere_notification.id)
    end
  end

  describe 'tenant isolation' do
    it 'reaches nothing in another account even with membership there' do
      other = create(:account)
      other_inbox_elsewhere = create(:inbox, account: other)
      foreign = create(:conversation, account: other, inbox: other_inbox_elsewhere,
                                      contact: create(:contact, account: other))
      create(:account_user, account: other, user: agent, role: :agent)
      create(:inbox_member, inbox: other_inbox_elsewhere, user: agent)
      foreign_notification = agent.notifications.create!(account: other, primary_actor: foreign,
                                                         notification_type: 'conversation_assignment')

      expect(listed_ids).not_to include(foreign_notification.id)
      expect(probe(foreign_notification)).to eq(404)
    end
  end
end
