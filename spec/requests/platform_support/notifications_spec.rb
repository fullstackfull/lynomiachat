require 'rails_helper'
require_relative 'security/platform_support_contract_stub'

# THE SIX PROOFS §5 REQUIRES, plus the two cross-type collisions the second actor type made destructive.
#
# The notification path is the riskiest change in this module: `notifications` has no foreign keys at all, its
# `uniq_primary_actor_per_account_notifications` index is not unique despite the name, and `primary_actor_id`
# is an id WITHIN a type. So the dangerous failure here is not a refusal -- it is a silent WRONG ANSWER by id
# collision, in either direction. Several examples below construct exactly that collision deliberately, by
# pointing a notification's `primary_actor_id` at an id of the other type; they are the proof that the
# per-type branches in `narrow` and `permits?` are doing the work and that a longer allow-list alone would
# have been a defect.
RSpec.describe 'Platform Support notifications', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:reporter) { create(:user, account: account, role: :agent) }
  let(:bystander) { create(:user, account: account, role: :agent) }
  let(:other_administrator) { create(:user, account: other_account, role: :administrator) }

  let(:ticket) { PlatformSupportContractStub.ticket!(account: account, reporter: reporter) }

  def visibility(user, for_account: account)
    Notifications::ConversationVisibility.for(account: for_account, user: user)
  end

  def reply_row(user, actor, for_account: account)
    user.notifications.create!(account: for_account, notification_type: 'platform_support_reply',
                               primary_actor: actor)
  end

  # A row whose primary actor does not resolve, written to construct an id collision. Validation is skipped
  # deliberately: `belongs_to :primary_actor` is required, and the rows this stands for -- written by a
  # previous version, or by a type whose record was later removed -- are exactly what read-time
  # authorization exists to answer about.
  def dangling_row(user, type:, id:, notification_type: 'platform_support_reply')
    row = Notification.new(user: user, account: account, notification_type: notification_type,
                           primary_actor_type: type, primary_actor_id: id)
    row.save!(validate: false)
    row
  end

  def feed_for(user)
    get "/api/v1/accounts/#{account.id}/notifications", headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['data']
  end

  # ---- PROOF 1: the intended actor is explicitly allowed -------------------------------------------------
  describe 'the intended actor' do
    it 'allows a platform support reply notification for the reporter' do
      row = reply_row(reporter, ticket)

      expect(visibility(reporter).permits?(row)).to be true
      expect(visibility(reporter).narrow(reporter.notifications)).to include(row)
    end

    it 'allows it for an administrator of the subject account, who sees every ticket of their account' do
      row = reply_row(administrator, ticket)

      expect(visibility(administrator).permits?(row)).to be true
      expect(visibility(administrator).narrow(administrator.notifications)).to include(row)
    end

    it 'serves it through the feed endpoint without raising' do
      row = reply_row(reporter, ticket)

      expect(feed_for(reporter)['payload'].pluck('id')).to contain_exactly(row.id)
    end

    it 'keeps the allow-list in step with Notification::PRIMARY_ACTORS' do
      expect(Notifications::ConversationVisibility::VISIBLE_ACTOR_TYPES).to eq(Notification::PRIMARY_ACTORS)
      expect(Notifications::ConversationVisibility::VISIBLE_ACTOR_TYPES).to include('PlatformSupport::Ticket')
    end
  end

  # ---- PROOF 2: an account mismatch is denied -----------------------------------------------------------
  describe 'an account mismatch' do
    it 'denies a row whose account_id is not the account being asked about' do
      row = reply_row(administrator, ticket, for_account: other_account)

      expect(visibility(administrator, for_account: account).permits?(row)).to be false
    end

    # The ticket's own account, not only the notification's. An administrator short-circuit that did not look
    # at the ticket would answer yes here.
    it 'denies a row about a ticket belonging to another account' do
      foreign_ticket = PlatformSupportContractStub.ticket!(account: other_account)
      row = reply_row(administrator, foreign_ticket)

      expect(visibility(administrator).permits?(row)).to be false
      expect(visibility(administrator).narrow(administrator.notifications)).not_to include(row)
    end

    # An orphaned ticket -- its subject account deleted, `account_id` NULL, `account_name_at_creation` kept --
    # stops being readable by any tenant. A nil must never compare equal to an account id.
    it 'denies a row about an orphaned ticket whose account_id is NULL' do
      row = reply_row(administrator, ticket)
      ticket.update!(account_id: nil)

      expect(visibility(administrator).permits?(row.reload)).to be false
      expect(visibility(administrator).narrow(administrator.notifications)).not_to include(row)
    end
  end

  # ---- PROOF 3: an unknown actor type is still denied ---------------------------------------------------
  describe 'an actor type nobody authorized' do
    it 'denies it for an administrator, who is otherwise unrestricted' do
      row = administrator.notifications.create!(account: account, primary_actor: contact,
                                                notification_type: 'conversation_assignment')

      expect(visibility(administrator).unrestricted?).to be true
      expect(visibility(administrator).permits?(row)).to be false
      expect(visibility(administrator).narrow(administrator.notifications)).not_to include(row)
    end

    it 'denies a type that is not on the allow-list even when its id would resolve' do
      row = dangling_row(administrator, type: 'Account', id: account.id,
                                        notification_type: 'conversation_assignment')

      expect(visibility(administrator).permits?(row)).to be false
      expect(visibility(administrator).narrow(administrator.notifications)).not_to include(row)
    end

    it 'leaves the feed empty rather than serving an unauthorized type' do
      dangling_row(administrator, type: 'Account', id: account.id, notification_type: 'conversation_assignment')

      expect(feed_for(administrator)['payload']).to be_empty
    end
  end

  # ---- PROOF 4: a tenant cannot see another account's platform support notification ---------------------
  describe 'cross-account visibility through the feed' do
    it 'does not serve another account administrator a row about this accountticket' do
      reply_row(other_administrator, ticket, for_account: other_account)

      get "/api/v1/accounts/#{other_account.id}/notifications",
          headers: other_administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['data']['payload']).to be_empty
      expect(response.body).not_to include(ticket.reference)
    end

    # D-1's agent half: a plain agent of the SAME account sees only the tickets they reported, so a row
    # written for a bystander is hidden even though the account matches.
    it 'does not serve a bystander agent a row about a ticket somebody else reported' do
      row = reply_row(bystander, ticket)

      expect(visibility(bystander).permits?(row)).to be false
      expect(feed_for(bystander)['payload']).to be_empty
    end

    it 'serves a custom-role holder exactly what it serves a plain agent' do
      account.enable_features!('custom_roles')
      account.account_users.find_by(user: bystander)
             .update!(custom_role: create(:custom_role, account: account, permissions: ['conversation_manage']),
                      role: :agent)
      row = reply_row(bystander, ticket)

      expect(visibility(bystander.reload).permits?(row)).to be false
    end

    it 'denies every type for a user who is no longer a member of the account' do
      row = reply_row(reporter, ticket)
      account.account_users.find_by(user: reporter).destroy!

      expect(visibility(reporter.reload).permits?(row.reload)).to be false
    end
  end

  # ---- The §B-3 collision, in both directions ----------------------------------------------------------
  #
  # This is what a longer allow-list ALONE would have got wrong: `narrow` used to apply the conversation
  # subselect to the whole allowed set, so a ticket id would have been compared against conversation ids.
  describe 'cross-type id collision' do
    let!(:reachable_conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, assignee: reporter)
    end

    before { create(:inbox_member, inbox: inbox, user: reporter) }

    it 'does not authorize a ticket row because a reachable CONVERSATION shares its id' do
      row = dangling_row(reporter, type: 'PlatformSupport::Ticket', id: reachable_conversation.id)

      expect(visibility(reporter).permits?(row)).to be false
      expect(visibility(reporter).narrow(reporter.notifications)).not_to include(row)
    end

    it 'does not authorize a conversation row because a readable TICKET shares its id' do
      row = dangling_row(reporter, type: 'Conversation', id: ticket.id,
                                   notification_type: 'conversation_assignment')

      expect(visibility(reporter).permits?(row)).to be false
      expect(visibility(reporter).narrow(reporter.notifications)).not_to include(row)
    end

    it 'serves both types at once, each narrowed by its own rule' do
      ticket_row = reply_row(reporter, ticket)
      conversation_row = reporter.notifications.create!(account: account, primary_actor: reachable_conversation,
                                                        notification_type: 'conversation_assignment')

      expect(visibility(reporter).narrow(reporter.notifications))
        .to contain_exactly(ticket_row, conversation_row)
    end
  end

  # ---- PROOF 5: an internal note never produces a tenant-visible notification --------------------------
  describe 'an internal note' do
    it 'writes no notification row of any kind' do
      expect do
        PlatformSupport::InternalNote.create!(ticket: ticket, agent_id: 1, author_name: 'An operator',
                                              body: 'ESCALATE-TO-INFRA')
      end.not_to change(Notification, :count)
    end

    # There is one writer and it takes a ticket, not a note: no entry point exists through which a note could
    # become a notification.
    it 'has no notifier that accepts one' do
      expect(PlatformSupport::Notifications::ReplyNotifier.instance_method(:initialize).parameters)
        .to eq([[:keyreq, :ticket]])
      expect(Notification::NOTIFICATION_TYPES.keys.grep(/note/)).to be_empty
    end

    it 'keeps the note body out of the notification feed' do
      PlatformSupport::InternalNote.create!(ticket: ticket, agent_id: 1, author_name: 'An operator',
                                            body: 'ESCALATE-TO-INFRA')
      reply_row(reporter, ticket)

      expect(feed_for(reporter).to_json).not_to include('ESCALATE-TO-INFRA')
    end
  end

  # ---- PROOF 6: one operator reply produces no duplicate storm -----------------------------------------
  describe 'one operator public reply' do
    it 'writes exactly one row per eligible recipient' do
      rows = nil
      [ticket, administrator]

      expect { rows = PlatformSupport::Notifications::ReplyNotifier.new(ticket: ticket).perform }
        .to change(Notification, :count).by(2)

      expect(rows.map(&:user)).to contain_exactly(reporter, administrator)
      expect(rows.map(&:notification_type).uniq).to eq(['platform_support_reply'])
    end

    it 'writes one row, not two, for a reporter who is also an administrator' do
      self_served = PlatformSupportContractStub.ticket!(account: account, reporter: administrator)

      rows = PlatformSupport::Notifications::ReplyNotifier.new(ticket: self_served).perform

      expect(rows.map(&:user)).to eq([administrator])
    end

    it 'writes nothing for a bystander agent who cannot read the ticket' do
      bystander

      rows = PlatformSupport::Notifications::ReplyNotifier.new(ticket: ticket).perform

      expect(rows.map(&:user)).not_to include(bystander)
    end

    it 'writes nothing at all for an orphaned ticket' do
      ticket.update!(account_id: nil)

      expect { PlatformSupport::Notifications::ReplyNotifier.new(ticket: ticket).perform }
        .not_to change(Notification, :count)
    end

    # The operator's identity never reaches the bell: the feed serializer emits
    # `secondary_actor.push_event_data`, and the default would have been the acting operator.
    it 'leaves the secondary actor nil so no operator name is serialized' do
      rows = PlatformSupport::Notifications::ReplyNotifier.new(ticket: ticket).perform

      expect(rows.map(&:secondary_actor)).to all(be_nil)
    end

    it 'leaves the recipient with one row after a second and third reply' do
      # Built before `perform_enqueued_jobs`, which would otherwise also run the avatar-fetch job the user
      # factory enqueues and attempt a real HTTP request.
      [ticket, administrator]

      3.times do
        perform_enqueued_jobs do
          PlatformSupport::Notifications::ReplyNotifier.new(ticket: ticket).perform
        end
      end

      expect(reporter.notifications.where(primary_actor: ticket).count).to eq(1)
    end

    # The §B-4 collision: the dedup job keyed on `primary_actor_id` alone would have destroyed the
    # conversation notification that happens to share the ticket's id.
    it 'does not destroy a conversation notification that shares the ticket id' do
      conversation_row = dangling_row(reporter, type: 'Conversation', id: ticket.id,
                                                notification_type: 'conversation_assignment')

      perform_enqueued_jobs do
        PlatformSupport::Notifications::ReplyNotifier.new(ticket: ticket).perform
      end

      expect(Notification.exists?(conversation_row.id)).to be true
    end

    # And the dedup job is account-scoped: a user in two accounts keeps both rows.
    it 'does not destroy the same user row in another account' do
      create(:account_user, account: other_account, user: reporter, role: 'administrator')
      elsewhere = dangling_row(reporter, type: 'PlatformSupport::Ticket', id: ticket.id)
      # Straight to the column: the point is a row in ANOTHER account about the same actor, which no
      # application path would write, and which the dedup job must leave alone.
      elsewhere.update_columns(account_id: other_account.id) # rubocop:disable Rails/SkipsModelValidations

      perform_enqueued_jobs do
        PlatformSupport::Notifications::ReplyNotifier.new(ticket: ticket).perform
      end

      expect(Notification.exists?(elsewhere.id)).to be true
    end
  end

  # ---- Delivery: the bell only ------------------------------------------------------------------------
  describe 'delivery' do
    it 'never enqueues the conversation-shaped email or push job, even with the flag switched on' do
      setting = reporter.notification_settings.find_by(account_id: account.id)
      setting.selected_email_flags = [:email_platform_support_reply]
      setting.selected_push_flags = [:push_platform_support_reply]
      setting.save!

      expect(Notification::EmailNotificationJob).not_to receive(:perform_later)
      expect(Notification::PushNotificationJob).not_to receive(:perform_later)

      PlatformSupport::Notifications::ReplyNotifier.new(ticket: ticket).perform
    end

    it 'renders no title and no body for the type, which is the fail-safe' do
      row = reply_row(reporter, ticket)

      expect(row.push_message_title).to eq('')
      expect(row.push_message_body).to eq('')
    end
  end
end
