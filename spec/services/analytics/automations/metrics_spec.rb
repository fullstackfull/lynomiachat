require 'rails_helper'

RSpec.describe Analytics::Automations::Metrics do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:other_account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:rule) do
    create(:automation_rule, account: account, name: 'Chase the customer', event_name: 'conversation_resolved',
                             execution_delay: 30)
  end
  let(:other_rule) do
    create(:automation_rule, account: account, name: 'Nudge the agent', event_name: 'conversation_resolved',
                             execution_delay: 60)
  end

  # Inside the 30-day retention window, so the range itself never triggers the retention warning.
  let(:since_date) { 6.days.ago.to_date }
  let(:until_date) { Date.current }
  let(:outcome_at) { 3.days.ago }

  let(:date_range) do
    Analytics::DateRange.new(account: account, since: since_date.to_s, until_value: until_date.to_s, group_by: 'day')
  end

  def metrics(filters: {})
    described_class.new(
      account: account, date_range: date_range,
      filters: Analytics::FilterSet.new(account: account, family: :automations, params: filters)
    )
  end

  # created_at and updated_at are passed in rather than written afterwards: Rails only stamps them when they are
  # not already set, so the row is inserted with the times each example needs.
  def execution(status:, for_rule: nil, at: nil, skip_reason: nil, created: nil)
    AutomationRulePendingExecution.create!(
      automation_rule: for_rule || rule, conversation: conversation, account_id: account.id,
      episode_key: "status:#{SecureRandom.hex(6)}", due_at: 1.hour.from_now, status: status,
      skip_reason: skip_reason, created_at: created || outcome_at, updated_at: at || outcome_at
    )
  end

  describe 'executed and skipped' do
    it 'counts terminal rows by when they reached their outcome' do
      execution(status: :executed)
      execution(status: :executed)
      execution(status: :skipped, skip_reason: 'episode_ended')
      execution(status: :pending)

      expect(metrics.executed).to eq(2)
      expect(metrics.skipped).to eq(1)
    end

    it 'excludes an outcome that landed outside the range' do
      execution(status: :executed, at: 40.days.ago, created: 40.days.ago)
      expect(metrics.executed).to eq(0)
    end

    it "never counts another account's executions" do
      other_inbox = create(:inbox, account: other_account)
      other_conversation = create(:conversation, account: other_account, inbox: other_inbox,
                                                 contact: create(:contact, account: other_account))
      foreign_rule = create(:automation_rule, account: other_account, event_name: 'conversation_resolved',
                                              execution_delay: 30)
      AutomationRulePendingExecution.create!(
        automation_rule: foreign_rule, conversation: other_conversation, account_id: other_account.id,
        episode_key: 'status:1', due_at: 1.hour.from_now, status: :executed,
        created_at: outcome_at, updated_at: outcome_at
      )

      expect(metrics.executed).to eq(0)
    end
  end

  describe 'episodes_armed' do
    it 'counts rows by when they were armed, not when they finished' do
      execution(status: :executed, created: outcome_at, at: outcome_at)
      execution(status: :executed, created: 40.days.ago, at: outcome_at)

      expect(metrics.episodes_armed).to eq(1)
      expect(metrics.executed).to eq(2)
    end
  end

  describe 'execution_rate' do
    it 'is the share of outcomes that acted' do
      execution(status: :executed)
      execution(status: :executed)
      execution(status: :executed)
      execution(status: :skipped, skip_reason: 'episode_ended')

      expect(metrics.execution_rate).to eq(75.0)
    end

    it 'returns nil rather than zero when nothing reached an outcome' do
      execution(status: :pending)
      expect(metrics.execution_rate).to be_nil
    end
  end

  describe 'current state' do
    it 'counts episodes still bound to fire, whatever the range' do
      execution(status: :pending, created: 40.days.ago, at: 40.days.ago)
      execution(status: :processing, created: 40.days.ago, at: 40.days.ago)
      execution(status: :executed)

      expect(metrics.awaiting_now).to eq(2)
    end

    it 'counts rows whose worker died while the actions were running' do
      execution(status: :executing, at: 1.hour.ago)

      expect(metrics.stranded_now).to eq(1)
    end

    it 'does not count a live executing row as stranded' do
      execution(status: :executing, at: Time.current)
      expect(metrics.stranded_now).to eq(0)
    end
  end

  describe 'what this family cannot report' do
    it 'counts the account rules that leave no execution record' do
      rule
      create(:automation_rule, account: account, event_name: 'conversation_created', execution_delay: nil)

      expect(metrics.immediate_rule_count).to eq(1)
    end

    it 'reports a range that reaches past the 30-day retention window' do
      wide = Analytics::DateRange.new(account: account, since: 90.days.ago.to_date.to_s,
                                      until_value: Date.current.to_s, group_by: 'month')
      wide_metrics = described_class.new(
        account: account, date_range: wide,
        filters: Analytics::FilterSet.new(account: account, family: :automations, params: {})
      )

      expect(wide_metrics.range_exceeds_retention?).to be(true)
      expect(metrics.range_exceeds_retention?).to be(false)
    end
  end

  describe 'filters' do
    it 'narrows to one rule' do
      execution(status: :executed)
      execution(status: :executed, for_rule: other_rule)

      expect(metrics(filters: { 'automation_rule_id' => rule.id }).executed).to eq(1)
    end

    it 'refuses a rule id from another account' do
      foreign = create(:automation_rule, account: other_account, event_name: 'conversation_created')

      expect { metrics(filters: { 'automation_rule_id' => foreign.id }) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::UnknownFilterValue') })
    end
  end

  describe 'series' do
    it 'emits one point per bucket including the zeros' do
      execution(status: :executed)
      points = metrics.series(:executed)

      expect(points.length).to eq(7)
      expect(points.sum { |point| point[:value] }).to eq(1)
    end
  end

  describe 'breakdowns' do
    it 'groups outcomes by rule, labelled with the rule name' do
      execution(status: :executed)
      execution(status: :executed)
      execution(status: :executed, for_rule: other_rule)

      expect(metrics.breakdown(:rule).first).to eq(id: rule.id, label: 'Chase the customer', value: 2)
    end

    it 'groups skips by the reason the runner recorded' do
      execution(status: :skipped, skip_reason: 'episode_ended')
      execution(status: :skipped, skip_reason: 'episode_ended')
      execution(status: :skipped, skip_reason: 'conditions_not_met')

      expect(metrics.breakdown(:skip_reason).first).to eq(id: 'episode_ended', label: 'episode_ended', value: 2)
    end

    it 'groups by status' do
      execution(status: :executed)
      execution(status: :skipped, skip_reason: 'episode_ended')

      expect(metrics.breakdown(:status).map { |row| row[:label] }).to contain_exactly('executed', 'skipped')
    end
  end
end
