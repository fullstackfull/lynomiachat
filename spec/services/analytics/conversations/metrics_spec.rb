require 'rails_helper'

RSpec.describe Analytics::Conversations::Metrics do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account_inbox) { create(:inbox, account: other_account) }
  let(:other_account_contact) { create(:contact, account: other_account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  let(:date_range) do
    Analytics::DateRange.new(account: account, since: '2026-10-01', until_value: '2026-10-07', group_by: 'day')
  end

  def metrics(filters: {})
    described_class.new(
      account: account, date_range: date_range,
      filters: Analytics::FilterSet.new(account: account, family: :conversations, params: filters)
    )
  end

  def conversation_at(time, status: :open, for_inbox: inbox, team: nil, assignee: nil)
    create(:conversation, account: account, inbox: for_inbox, contact: contact,
                          status: status, team: team, assignee: assignee, created_at: time)
  end

  def event(name, conversation, at:, start_time: nil, value: 0)
    ReportingEvent.create!(
      name: name, value: value, account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      conversation_id: conversation.id, created_at: at,
      event_start_time: start_time || conversation.created_at, event_end_time: at
    )
  end

  describe 'conversations_created' do
    it 'counts conversations created inside the account-timezone window' do
      conversation_at(Time.utc(2026, 10, 1, 10, 0))
      # 22:00 UTC on 30 September is 1 October in Kuwait, so it belongs to this range.
      conversation_at(Time.utc(2026, 9, 30, 22, 0))
      # 20:00 UTC on 30 September is still 30 September locally, so it does not.
      conversation_at(Time.utc(2026, 9, 30, 20, 0))

      expect(metrics.conversations_created).to eq(2)
    end

    it "never counts another account's conversations" do
      create(:conversation, account: other_account, inbox: other_account_inbox,
                            contact: other_account_contact, created_at: Time.utc(2026, 10, 1, 10, 0))

      expect(metrics.conversations_created).to eq(0)
    end
  end

  describe 'conversations_reopened' do
    it 'does not count a first open' do
      conversation = conversation_at(Time.utc(2026, 10, 1, 9, 0))
      event('conversation_opened', conversation, at: Time.utc(2026, 10, 1, 9, 0),
                                                 start_time: conversation.created_at)

      expect(metrics.conversations_reopened).to eq(0)
    end

    it 'counts resolved -> reopened as one reopen' do
      conversation = conversation_at(Time.utc(2026, 10, 1, 9, 0))
      resolved_at = Time.utc(2026, 10, 2, 9, 0)
      event('conversation_resolved', conversation, at: resolved_at)
      event('conversation_opened', conversation, at: Time.utc(2026, 10, 3, 9, 0), start_time: resolved_at)

      expect(metrics.conversations_reopened).to eq(1)
    end

    it 'counts resolved -> reopened -> resolved -> reopened as two reopens' do
      conversation = conversation_at(Time.utc(2026, 10, 1, 9, 0))
      first_resolve = Time.utc(2026, 10, 2, 9, 0)
      second_resolve = Time.utc(2026, 10, 4, 9, 0)
      event('conversation_resolved', conversation, at: first_resolve)
      event('conversation_opened', conversation, at: Time.utc(2026, 10, 3, 9, 0), start_time: first_resolve)
      event('conversation_resolved', conversation, at: second_resolve)
      event('conversation_opened', conversation, at: Time.utc(2026, 10, 5, 9, 0), start_time: second_resolve)

      expect(metrics.conversations_reopened).to eq(2)
    end

    it 'counts a reopen that happened in the same second as its resolution, which value > 0 would miss' do
      conversation = conversation_at(Time.utc(2026, 10, 1, 9, 0))
      resolved_at = Time.utc(2026, 10, 2, 9, 0)
      event('conversation_resolved', conversation, at: resolved_at)
      event('conversation_opened', conversation, at: resolved_at, start_time: resolved_at, value: 0)

      expect(metrics.conversations_reopened).to eq(1)
    end

    it "never counts another account's reopens" do
      conversation = create(:conversation, account: other_account, inbox: other_account_inbox,
                                           contact: other_account_contact, created_at: Time.utc(2026, 10, 1, 9, 0))
      event('conversation_opened', conversation, at: Time.utc(2026, 10, 3, 9, 0),
                                                 start_time: Time.utc(2026, 10, 2, 9, 0))

      expect(metrics.conversations_reopened).to eq(0)
    end
  end

  describe 'unresolved_backlog' do
    it 'counts open and pending but not resolved' do
      conversation_at(Time.utc(2026, 10, 1, 9, 0), status: :open)
      conversation_at(Time.utc(2026, 10, 1, 9, 0), status: :pending)
      conversation_at(Time.utc(2026, 10, 1, 9, 0), status: :resolved)

      expect(metrics.unresolved_backlog).to eq(2)
    end

    it 'excludes snoozed, which is deliberately out of the queue' do
      conversation_at(Time.utc(2026, 10, 1, 9, 0), status: :snoozed)
      expect(metrics.unresolved_backlog).to eq(0)
    end

    it 'is current state, so it includes conversations created outside the requested range' do
      conversation_at(Time.utc(2020, 1, 1, 9, 0), status: :open)
      expect(metrics.unresolved_backlog).to eq(1)
      expect(metrics.conversations_created).to eq(0)
    end
  end

  describe 'message counts' do
    def message(type, at:, private_note: false, for_inbox: inbox)
      conversation = conversation_at(Time.utc(2026, 10, 1, 8, 0), for_inbox: for_inbox)
      create(:message, account: account, inbox: for_inbox, conversation: conversation,
                       message_type: type, private: private_note, created_at: at)
    end

    it 'counts inbound and outbound separately' do
      message(:incoming, at: Time.utc(2026, 10, 1, 10, 0))
      message(:incoming, at: Time.utc(2026, 10, 2, 10, 0))
      message(:outgoing, at: Time.utc(2026, 10, 2, 11, 0))

      expect(metrics.inbound_messages).to eq(2)
      expect(metrics.outbound_messages).to eq(1)
    end

    it 'excludes activity rows, which are not customer communication' do
      message(:activity, at: Time.utc(2026, 10, 1, 10, 0))
      expect(metrics.inbound_messages + metrics.outbound_messages).to eq(0)
    end

    it 'excludes private notes' do
      message(:outgoing, at: Time.utc(2026, 10, 1, 10, 0), private_note: true)
      expect(metrics.outbound_messages).to eq(0)
    end

    it 'excludes system templates such as greeting and CSAT, which carry message_type template' do
      message(:template, at: Time.utc(2026, 10, 1, 10, 0))
      expect(metrics.outbound_messages).to eq(0)
    end
  end

  describe 'averages' do
    it 'returns nil rather than zero when nothing was resolved, so no data is not shown as instant' do
      expect(metrics.avg_resolution_time).to be_nil
    end

    it 'averages the stored durations without recomputing them' do
      conversation = conversation_at(Time.utc(2026, 10, 1, 9, 0))
      event('conversation_resolved', conversation, at: Time.utc(2026, 10, 2, 9, 0), value: 100)
      event('conversation_resolved', conversation, at: Time.utc(2026, 10, 3, 9, 0), value: 300)

      expect(metrics.avg_resolution_time).to eq(200.0)
    end
  end

  describe 'filters' do
    it 'restricts conversations to one inbox' do
      conversation_at(Time.utc(2026, 10, 1, 9, 0), for_inbox: inbox)
      conversation_at(Time.utc(2026, 10, 1, 9, 0), for_inbox: other_inbox)

      expect(metrics(filters: { inbox_id: inbox.id }).conversations_created).to eq(1)
    end

    it 'restricts conversations to one agent' do
      conversation_at(Time.utc(2026, 10, 1, 9, 0), assignee: agent)
      conversation_at(Time.utc(2026, 10, 1, 9, 0))

      expect(metrics(filters: { agent_id: agent.id }).conversations_created).to eq(1)
    end

    it 'restricts conversations to one team' do
      team = create(:team, account: account)
      conversation_at(Time.utc(2026, 10, 1, 9, 0), team: team)
      conversation_at(Time.utc(2026, 10, 1, 9, 0))

      expect(metrics(filters: { team_id: team.id }).conversations_created).to eq(1)
    end
  end

  describe 'series' do
    it 'emits one point per bucket including the zeros' do
      conversation_at(Time.utc(2026, 10, 1, 10, 0))
      points = metrics.series(:conversations_created)

      expect(points.length).to eq(7)
      expect(points.first).to eq(bucket: '2026-10-01', value: 1)
      expect(points.sum { |point| point[:value] }).to eq(1)
    end

    it 'buckets by the account timezone, not naive UTC' do
      conversation_at(Time.utc(2026, 10, 1, 22, 0))
      points = metrics.series(:conversations_created)

      expect(points.find { |point| point[:bucket] == '2026-10-02' }[:value]).to eq(1)
      expect(points.find { |point| point[:bucket] == '2026-10-01' }[:value]).to eq(0)
    end
  end

  describe 'breakdowns' do
    it 'groups by inbox with names' do
      conversation_at(Time.utc(2026, 10, 1, 9, 0), for_inbox: inbox)
      conversation_at(Time.utc(2026, 10, 1, 9, 0), for_inbox: inbox)
      conversation_at(Time.utc(2026, 10, 1, 9, 0), for_inbox: other_inbox)

      rows = metrics.breakdown(:inbox)
      expect(rows.first).to eq(id: inbox.id, label: inbox.name, value: 2)
    end

    it 'groups by channel through the inbox, since conversations carry no channel column' do
      conversation_at(Time.utc(2026, 10, 1, 9, 0))
      rows = metrics.breakdown(:channel)

      expect(rows.first[:label]).to eq(inbox.channel_type.delete_prefix('Channel::'))
    end

    it 'omits unassigned conversations from the agent breakdown rather than inventing a bucket' do
      conversation_at(Time.utc(2026, 10, 1, 9, 0), assignee: nil)
      expect(metrics.breakdown(:agent)).to be_empty
    end
  end
end
