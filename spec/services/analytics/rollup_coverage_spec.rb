require 'rails_helper'

RSpec.describe Analytics::RollupCoverage do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:date_range) do
    Analytics::DateRange.new(account: account, since: '2026-10-01', until_value: '2026-10-02', group_by: 'day')
  end

  def decide(for_account: account, metric: :resolutions_count, family: :conversations, dimension_type: 'account')
    range = Analytics::DateRange.new(account: for_account, since: '2026-10-01', until_value: '2026-10-02', group_by: 'day')
    described_class.new(account: for_account, date_range: range, family: family, metric: metric,
                        dimension_type: dimension_type).decide
  end

  # Two events at 22:00 and 23:30 UTC on 1 October are 2 October in Kuwait, so the rollup the writer would have
  # produced puts one row on the 1st and two on the 2nd. Matching that exactly is what "coverage" means.
  def create_resolved_events
    [
      Time.utc(2026, 10, 1, 10, 0, 0),
      Time.utc(2026, 10, 1, 22, 0, 0),
      Time.utc(2026, 10, 1, 23, 30, 0)
    ].each do |at|
      ReportingEvent.create!(account_id: account.id, name: 'conversation_resolved', value: 1, created_at: at)
    end
  end

  def create_rollup(date, count)
    ReportingEventsRollup.create!(
      account_id: account.id, date: date, dimension_type: 'account', dimension_id: account.id,
      metric: 'resolutions_count', count: count, sum_value: 0, sum_value_business_hours: 0
    )
  end

  describe 'the four conditions that must all hold' do
    it 'reads raw when the report_rollup read feature is off, which is the default' do
      decision = decide
      expect(decision.source).to eq(:raw)
      expect(decision.reason).to eq(:feature_disabled)
    end

    context 'with the feature enabled' do
      before { account.enable_features!('report_rollup') }

      it 'reads raw when the account has no reporting timezone, because nothing was ever written' do
        no_zone = create(:account)
        no_zone.enable_features!('report_rollup')

        decision = decide(for_account: no_zone)
        expect(decision.source).to eq(:raw)
        expect(decision.reason).to eq(:no_account_reporting_timezone)
      end

      it 'reads raw for a dimension the rollup writer does not populate' do
        decision = decide(dimension_type: 'team')
        expect(decision.source).to eq(:raw)
        expect(decision.reason).to eq(:no_rollup_dimension)
      end

      it 'reads raw for a metric with no rollup counterpart' do
        decision = decide(metric: :conversations_count)
        expect(decision.source).to eq(:raw)
        expect(decision.reason).to eq(:no_rollup_metric)
      end

      it 'reads raw when the rollup table is empty for the range' do
        create_resolved_events

        decision = decide
        expect(decision.source).to eq(:raw)
        expect(decision.reason).to eq(:incomplete_coverage)
      end

      it 'reads raw when a day inside the range is missing from the rollup' do
        create_resolved_events
        create_rollup('2026-10-01', 1)

        expect(decide.reason).to eq(:incomplete_coverage)
      end

      it 'reads raw when the rollup disagrees with the raw events, as an additive double count would' do
        create_resolved_events
        create_rollup('2026-10-01', 2)
        create_rollup('2026-10-02', 4)

        expect(decide.reason).to eq(:incomplete_coverage)
      end

      it 'uses the rollup only when every bucket matches the raw events for the same account-timezone days' do
        create_resolved_events
        create_rollup('2026-10-01', 1)
        create_rollup('2026-10-02', 2)

        decision = decide
        expect(decision.source).to eq(:rollup)
        expect(decision.reason).to eq(:coverage_verified)
        expect(decision).to be_rollup
      end

      it 'does not accept a rollup that was bucketed by naive UTC days instead of account days' do
        create_resolved_events
        # What a UTC bucketer would have written: all three events on 1 October.
        create_rollup('2026-10-01', 3)

        expect(decide.reason).to eq(:incomplete_coverage)
      end
    end
  end

  describe 'account isolation' do
    before { account.enable_features!('report_rollup') }

    it "never reads another account's rollup rows as coverage" do
      create_resolved_events
      other = create(:account, reporting_timezone: 'Asia/Kuwait')
      ReportingEventsRollup.create!(
        account_id: other.id, date: '2026-10-01', dimension_type: 'account', dimension_id: other.id,
        metric: 'resolutions_count', count: 1, sum_value: 0, sum_value_business_hours: 0
      )
      ReportingEventsRollup.create!(
        account_id: other.id, date: '2026-10-02', dimension_type: 'account', dimension_id: other.id,
        metric: 'resolutions_count', count: 2, sum_value: 0, sum_value_business_hours: 0
      )

      expect(decide.reason).to eq(:incomplete_coverage)
    end

    it "never counts another account's raw events toward this account's coverage" do
      other = create(:account, reporting_timezone: 'Asia/Kuwait')
      ReportingEvent.create!(account_id: other.id, name: 'conversation_resolved', value: 1,
                             created_at: Time.utc(2026, 10, 1, 10, 0, 0))
      create_rollup('2026-10-01', 1)

      # This account has no raw events of its own. A rollup row claiming one must not be accepted on the strength
      # of another account's event, and an empty raw side must not be treated as agreeing with a non-empty rollup.
      expect(decide.reason).to eq(:incomplete_coverage)
      expect(decide.source).to eq(:raw)
    end

    it 'refuses a rollup row for a day the account has no raw events on' do
      create_rollup('2026-10-01', 7)

      expect(decide.reason).to eq(:incomplete_coverage)
    end

    it 'reads raw when both sides are empty, rather than claiming verified coverage over nothing' do
      decision = decide
      expect(decision.source).to eq(:raw)
      expect(decision.reason).to eq(:incomplete_coverage)
    end
  end
end
