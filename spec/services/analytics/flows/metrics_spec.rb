require 'rails_helper'

RSpec.describe Analytics::Flows::Metrics do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil, name: 'Welcome') }
  let(:other_bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil, name: 'Returns') }
  let(:version) { flow_version(bot) }

  let(:date_range) do
    Analytics::DateRange.new(account: account, since: '2026-10-01', until_value: '2026-10-07', group_by: 'day')
  end

  def metrics(filters: {})
    described_class.new(
      account: account, date_range: date_range,
      filters: Analytics::FilterSet.new(account: account, family: :flows, params: filters)
    )
  end

  def flow_version(for_bot)
    FlowVersion.create!(account: for_bot.account, agent_bot: for_bot, version: FlowVersion.where(agent_bot: for_bot).count + 1,
                        status: :published, graph: { 'nodes' => [], 'edges' => [] })
  end

  # created_at is passed in rather than written afterwards: Rails only stamps it when it is not already set, so
  # the row is inserted with the start time each example needs.
  def session(status:, started: Time.utc(2026, 10, 2, 9, 0), finished: Time.utc(2026, 10, 2, 10, 0), **attributes)
    owner = attributes[:for_bot] || bot
    conversation = create(:conversation, account: account, inbox: attributes[:for_inbox] || inbox, contact: contact)
    end_reason = attributes[:end_reason]
    FlowSession.create!(
      account: account, agent_bot: owner, flow_version: attributes[:for_bot] ? flow_version(owner) : version,
      conversation: conversation, status: status, steps_count: attributes.fetch(:steps, 4),
      failure_code: attributes[:failure_code], finished_at: finished, created_at: started,
      context: end_reason ? { 'end_reason' => end_reason } : {}
    )
  end

  describe 'sessions_started' do
    it 'counts sessions that began inside the account-timezone window' do
      session(status: :completed)
      # 22:00 UTC on 30 September is 1 October in Kuwait, so it belongs to this range.
      session(status: :completed, started: Time.utc(2026, 9, 30, 22, 0))
      # 20:00 UTC on 30 September is still 30 September locally, so it does not.
      session(status: :completed, started: Time.utc(2026, 9, 30, 20, 0))

      expect(metrics.sessions_started).to eq(2)
    end

    it "never counts another account's sessions" do
      foreign_bot = create(:agent_bot, account: other_account, bot_type: :flow, outgoing_url: nil)
      foreign_inbox = create(:inbox, account: other_account)
      foreign_conversation = create(:conversation, account: other_account, inbox: foreign_inbox,
                                                   contact: create(:contact, account: other_account))
      FlowSession.create!(account: other_account, agent_bot: foreign_bot, flow_version: flow_version(foreign_bot),
                          conversation: foreign_conversation, status: :completed,
                          finished_at: Time.utc(2026, 10, 2, 10, 0))

      expect(metrics.sessions_started).to eq(0)
    end
  end

  describe 'outcomes' do
    it 'counts each terminal status by when the run ended' do
      session(status: :completed)
      session(status: :failed, failure_code: 'step_limit')
      session(status: :cancelled, end_reason: 'conversation_resolved')
      session(status: :handed_off, end_reason: 'Care asked')

      expect(metrics.sessions_completed).to eq(1)
      expect(metrics.sessions_failed).to eq(1)
      expect(metrics.sessions_cancelled).to eq(1)
      expect(metrics.handed_off).to eq(1)
    end

    it 'excludes a run that ended outside the range even if it started inside it' do
      session(status: :completed, finished: Time.utc(2026, 10, 20, 10, 0))

      expect(metrics.sessions_started).to eq(1)
      expect(metrics.sessions_completed).to eq(0)
    end

    it 'does not treat a still-waiting session as any outcome' do
      session(status: :waiting, finished: nil)

      expect(metrics.sessions_completed).to eq(0)
      expect(metrics.sessions_cancelled).to eq(0)
      expect(metrics.live_now).to eq(1)
    end
  end

  describe 'completion_rate' do
    it 'is the share of the period\'s endings that reached an End node' do
      session(status: :completed)
      session(status: :completed)
      session(status: :failed, failure_code: 'step_limit')
      session(status: :handed_off, end_reason: 'Care asked')

      expect(metrics.completion_rate).to eq(50.0)
    end

    it 'returns nil rather than zero when nothing ended' do
      session(status: :waiting, finished: nil)
      expect(metrics.completion_rate).to be_nil
    end
  end

  describe 'average_duration' do
    it 'is wall-clock seconds from start to end' do
      session(status: :completed, started: Time.utc(2026, 10, 2, 9, 0), finished: Time.utc(2026, 10, 2, 9, 30))
      session(status: :completed, started: Time.utc(2026, 10, 2, 9, 0), finished: Time.utc(2026, 10, 2, 9, 10))

      expect(metrics.average_duration).to eq(1200)
    end

    it 'returns nil rather than zero when nothing ended' do
      session(status: :active, finished: nil)
      expect(metrics.average_duration).to be_nil
    end
  end

  describe 'average_steps' do
    it 'averages the step count of the runs that ended' do
      session(status: :completed, steps: 4)
      session(status: :completed, steps: 7)

      expect(metrics.average_steps).to eq(5.5)
    end
  end

  describe 'live_now' do
    it 'counts active and waiting sessions whatever the range' do
      session(status: :active, started: Time.utc(2020, 1, 1), finished: nil)
      session(status: :waiting, started: Time.utc(2020, 1, 1), finished: nil)
      session(status: :completed)

      expect(metrics.live_now).to eq(2)
    end
  end

  describe 'filters' do
    it 'narrows to the sessions of conversations in one inbox' do
      session(status: :completed)
      session(status: :completed, for_inbox: other_inbox)

      expect(metrics(filters: { 'inbox_id' => inbox.id }).sessions_completed).to eq(1)
    end

    it 'refuses an inbox id from another account' do
      foreign = create(:inbox, account: other_account)

      expect { metrics(filters: { 'inbox_id' => foreign.id }) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::UnknownFilterValue') })
    end
  end

  describe 'series' do
    it 'emits one point per bucket including the zeros' do
      session(status: :completed, started: Time.utc(2026, 10, 1, 9, 0))
      points = metrics.series(:sessions_started)

      expect(points.length).to eq(7)
      expect(points.first).to eq(bucket: '2026-10-01', value: 1)
    end

    it 'buckets endings by the account timezone, not naive UTC' do
      session(status: :completed, started: Time.utc(2026, 10, 1, 9, 0), finished: Time.utc(2026, 10, 1, 22, 0))
      points = metrics.series(:sessions_completed)

      expect(points.find { |point| point[:bucket] == '2026-10-02' }[:value]).to eq(1)
    end
  end

  describe 'breakdowns' do
    it 'groups endings by bot, labelled with the bot name' do
      session(status: :completed)
      session(status: :completed)
      session(status: :completed, for_bot: other_bot)

      expect(metrics.breakdown(:bot).first).to eq(id: bot.id, label: 'Welcome', value: 2)
    end

    it 'groups failures by the code the runner recorded' do
      session(status: :failed, failure_code: 'step_limit')
      session(status: :failed, failure_code: 'step_limit')
      session(status: :failed, failure_code: 'template_not_found')

      expect(metrics.breakdown(:failure).first).to eq(id: 'step_limit', label: 'step_limit', value: 2)
    end

    it 'groups cancellations and handoffs by the reason stored in context' do
      session(status: :cancelled, end_reason: 'conversation_resolved')
      session(status: :handed_off, end_reason: 'Care asked')
      session(status: :completed)

      rows = metrics.breakdown(:end_reason)

      expect(rows.map { |row| row[:label] }).to contain_exactly('conversation_resolved', 'Care asked')
    end

    it 'groups by status' do
      session(status: :completed)
      session(status: :failed, failure_code: 'step_limit')

      expect(metrics.breakdown(:status).map { |row| row[:label] }).to contain_exactly('completed', 'failed')
    end
  end
end
