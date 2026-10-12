require 'rails_helper'

# The two things that cannot be asserted over HTTP.
#
# 1. A notification whose primary_actor is NOT a Conversation. No such row exists in this product -- every
#    NotificationBuilder call site passes a Conversation -- and the index renderer cannot serialize one either,
#    because Notification#push_message_title calls `display_id` on the primary actor unconditionally
#    (app/models/notification.rb:103-108). So the rule for an unauthorized actor type is asserted where it
#    lives, on the relation, rather than through a renderer that would raise for an unrelated reason.
#
#    THE DECISION THESE EXAMPLES NOW ENCODE IS THE OPPOSITE OF THE ONE THEY USED TO. Until Product Refinement
#    workstream E, `Notifications::ConversationVisibility` PASSED THROUGH any primary-actor type it did not
#    recognise, and three examples here asserted that pass-through as forward compatibility. It was not
#    forward compatibility, it was a default nobody chose: the first notification about something that is not
#    a tenant's conversation would have been published to every member of the account, unfiltered by the
#    Inbox/Team ceiling and unfiltered by the capability. The rule is now a positive allow-list
#    (`VISIBLE_ACTOR_TYPES`) and it is fail-closed, for every member including an administrator.
#
# 2. The query shape. The decision requires a bounded strategy rather than a policy check per row, and that is
#    a claim about SQL, not about a response body.
RSpec.describe NotificationFinder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:membership) { account.account_users.find_by(user: agent) }
  let(:contact) { create(:contact, account: account) }

  before do
    account.enable_features!('custom_roles')
    create(:inbox_member, inbox: inbox, user: agent)
  end

  def attach(*permissions)
    membership.update!(custom_role: create(:custom_role, account: account, permissions: permissions), role: :agent)
    membership.reload
  end

  def finder
    described_class.new(agent.reload, account, {})
  end

  describe 'a notification whose primary actor is not an authorized type' do
    let!(:foreign_actor_notification) do
      agent.notifications.create!(account: account, primary_actor: contact,
                                  notification_type: 'conversation_assignment')
    end
    let!(:conversation_notification) do
      agent.notifications.create!(account: account, notification_type: 'conversation_assignment',
                                  primary_actor: create(:conversation, account: account, inbox: inbox,
                                                                       contact: contact, assignee: other_agent))
    end

    it 'is refused in the narrowest mode, along with the conversation this member cannot reach' do
      attach('contact_manage')

      expect(finder.notifications).to be_empty
      # Hidden, not deleted. The allow-list is a read-time decision, so the row it refuses is still there --
      # which is what makes it reversible when somebody authorizes that actor type.
      expect(foreign_actor_notification.reload).to be_present
    end

    it 'is refused in the counts too, so the badge cannot advertise what the feed will not show' do
      attach('contact_manage')

      expect(finder.count).to be_zero
      expect(finder.unread_count).to be_zero
    end

    # The important one. A member with no narrowing at all -- an administrator -- is still not handed a kind of
    # notification nobody authorized them for. "Unrestricted" means unrestricted about WHICH CONVERSATIONS
    # they may reach, never about which kinds of thing they may be told about.
    it 'is refused even for a member nothing else narrows' do
      expect(finder.notifications).to contain_exactly(conversation_notification)
    end

    # The whole conversation path is unaffected by the allow-list: the member sees their own conversation's
    # notification, in every mode, exactly as before.
    it 'leaves the conversation notification alone in the narrowest mode that still reaches it' do
      mine = agent.notifications.create!(account: account, notification_type: 'conversation_assignment',
                                         primary_actor: create(:conversation, account: account, inbox: inbox,
                                                                              contact: contact, assignee: agent))
      attach('conversation_participating_manage')

      expect(finder.notifications).to contain_exactly(mine)
    end
  end

  describe 'the query shape, which must stay bounded' do
    let(:page_size) { NotificationFinder::RESULTS_PER_PAGE }

    before do
      # A realistic page: more notifications than fit on one, spread over more conversations than fit on one,
      # so a per-row strategy would show up as per-row queries.
      40.times do
        conversation = create(:conversation, account: account, inbox: inbox, contact: contact,
                                             assignee: [agent, other_agent, nil].sample)
        agent.notifications.create!(account: account, primary_actor: conversation,
                                    notification_type: 'conversation_assignment')
      end
    end

    def queries_for
      queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_n, _s, _f, _i, payload|
        next if payload[:name].in?(['SCHEMA', 'TRANSACTION', nil])

        queries << payload[:sql]
      end
      yield
      queries
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it 'loads one page with a single statement, narrowed, and no per-row authorization query' do
      attach('conversation_participating_manage')
      f = finder

      queries = queries_for { f.notifications.to_a }

      expect(queries.length).to eq(1)
      expect(queries.first).to include('IN (SELECT "conversations"."id"')
      expect(queries.first).to include('LIMIT')
    end

    # Measured across CONSTRUCTION as well as the page load, because the authorization lookups happen when the
    # relation is built (NotificationFinder#initialize -> set_up -> find_all_notifications), not when it is
    # loaded. Measuring only `.to_a` would have hidden them entirely.
    #
    # The page itself costs the same either way -- one statement. What narrowing adds is the fixed cost of
    # ASKING: reading the membership, its set, and the entitlement override. Fixed per request, not per row,
    # which is the property that matters.
    it 'adds a fixed per-request cost and no per-row cost' do
      attach('conversation_manage')
      unrestricted = queries_for { finder.notifications.to_a }

      attach('conversation_participating_manage')
      restricted = queries_for { finder.notifications.to_a }

      # Exactly one statement reads the notifications page. `LIMIT` alone is not a discriminator -- every
      # `find_by` in the authorization lookups emits one too.
      page_statements = restricted.count { |sql| sql.include?('FROM "notifications"') && sql.include?('LIMIT') }
      expect(page_statements).to eq(1)

      # And the conversations table is reached ONLY as a subselect inside that statement, never as a statement
      # of its own -- which is what "no per-row authorization query" means here.
      standalone_conversation_queries = restricted.count { |sql| sql.start_with?('SELECT "conversations"') }
      expect(standalone_conversation_queries).to eq(0)

      # The fixed cost of asking: the membership, its set, and the entitlement override.
      expect(restricted.length - unrestricted.length).to be <= 4
    end

    it 'never loads the authorized conversation ids into Ruby' do
      attach('conversation_participating_manage')
      f = finder

      queries = queries_for { f.notifications.to_a }

      # One statement total means the id set was a subselect, not a list materialized by a prior query.
      expect(queries.length).to eq(1)
      expect(queries.first.scan('SELECT').length).to be >= 2
    end

    # The property that matters, and the only one a test-sized table can honestly prove: the subselect is
    # UNCORRELATED, so Postgres evaluates it ONCE and probes a hash, rather than re-running it per notification
    # row. That is the difference between a bounded strategy and an N+1, and it holds at any table size.
    #
    # Deliberately NOT asserted here: index usage. At these row counts a sequential scan is the correct plan
    # and the planner picks it; an assertion about Index or Bitmap nodes would be asserting Postgres's size
    # heuristic rather than anything about this query. The indexes that serve it at production scale are
    # recorded in the closure report from db/schema.rb instead.
    it 'evaluates every authorization subselect once, not once per row' do
      attach('conversation_participating_manage')
      plan = ActiveRecord::Base.connection.execute(
        "EXPLAIN #{finder.notifications.to_sql}"
      ).map { |row| row['QUERY PLAN'] }.join("\n")

      # The property is that EVERY subselect is uncorrelated -- Postgres reports it as `hashed SubPlan N`,
      # meaning it ran once and the outer node probes a hash. A bare `SubPlan N` reference would be
      # re-executed per row, which is the N+1 this strategy exists to avoid.
      #
      # NOT a count of subselects. There used to be an assertion that at least three were declared, which
      # encoded the shape of the query rather than the property: making the visibility rule fail-closed
      # removed the `OR` from the WHERE clause, which let the planner flatten the authorized-conversation
      # subselect into a semi-join against `conversations` instead of running it as a third subplan. That is
      # strictly better, and an assertion that broke on it was asserting the wrong thing.
      #
      # Also deliberately NOT asserted: the absence of `Nested Loop`. There is one inside each membership
      # subplan, joining inboxes to inbox_members and teams to team_members. Each sits INSIDE a hashed
      # subplan, so it runs once over the member's own handful of memberships rather than once per
      # notification.
      declared = plan.scan(/^\s*SubPlan (\d+)$/).flatten
      hashed = plan.scan(/hashed SubPlan (\d+)/).flatten

      expect(declared).not_to be_empty
      expect(hashed.sort).to eq(declared.sort)
      # The conversation set is reached by a join or a hashed subplan, never by a per-row lookup.
      expect(plan).to include('conversations')
    end

    it 'keeps the page bounded to RESULTS_PER_PAGE and the count describing the narrowed set' do
      attach('conversation_participating_manage')
      f = finder

      expect(f.notifications.length).to be <= page_size
      expect(f.count).to eq(account.conversations.where(assignee_id: agent.id).count)
    end
  end
end
