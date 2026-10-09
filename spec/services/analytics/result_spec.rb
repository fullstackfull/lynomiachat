require 'rails_helper'

RSpec.describe Analytics::Result do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }
  let(:date_range) do
    Analytics::DateRange.new(account: account, since: '2026-10-01', until_value: '2026-10-03', group_by: 'day')
  end

  def build(**)
    described_class.new(family: :conversations, date_range: date_range, **)
  end

  describe 'meta' do
    it 'carries the timezone and the resolved window with every response' do
      expect(build.as_json[:meta]).to include(
        family: 'conversations', timezone: 'Asia/Kuwait', since: '2026-10-01', until: '2026-10-03',
        group_by: 'day', starts_at: '2026-09-30T21:00:00Z', ends_at: '2026-10-03T21:00:00Z',
        boundaries: 'start inclusive, end exclusive'
      )
    end

    it 'names the source and the reason it was chosen' do
      meta = build(source: :raw, source_reason: :feature_disabled).as_json[:meta]
      expect(meta).to include(source: 'raw', source_reason: 'feature_disabled')
    end

    it 'reports the resolved filters' do
      filters = Analytics::FilterSet.new(account: account, family: :conversations, params: {})
      expect(build(filters: filters).as_json[:meta][:filters]).to eq({})
    end
  end

  describe 'empty versus broken' do
    it 'is empty when every value is zero and nothing failed' do
      result = build.add_kpi(:conversations_count, 0).add_series(:volume, [{ bucket: '2026-10-01', value: 0 }])
      expect(result).to be_empty
      expect(result).not_to be_partial
    end

    it 'is not empty once a value is non-zero' do
      expect(build.add_kpi(:conversations_count, 3)).not_to be_empty
    end

    it 'is not empty when something failed, so no-data and broken never look alike' do
      result = build.add_kpi(:conversations_count, 0).degrade(:commerce, :adapter_unavailable)
      expect(result).not_to be_empty
      expect(result).to be_partial
    end

    it 'treats an empty breakdown as empty but a populated one as not' do
      expect(build.add_breakdown(:by_inbox, :inbox, [])).to be_empty
      expect(build.add_breakdown(:by_inbox, :inbox, [{ id: 1, label: 'Support', value: 2 }])).not_to be_empty
    end
  end

  describe 'degradation' do
    it 'records the scope and reason as a warning and flags the response partial' do
      json = build.degrade(:flows, :query_failed).as_json
      expect(json[:meta][:partial]).to be(true)
      expect(json[:meta][:warnings]).to eq([{ scope: 'flows', reason: 'query_failed' }])
    end

    it 'has no warnings and is not partial by default' do
      json = build.as_json
      expect(json[:meta][:partial]).to be(false)
      expect(json[:meta][:warnings]).to eq([])
    end
  end

  describe 'payload primitives' do
    it 'serialises a KPI, omitting an absent comparison' do
      json = build.add_kpi(:resolutions_count, 12, unit: :count).as_json
      expect(json[:kpis]).to eq([{ key: 'resolutions_count', value: 12, unit: 'count' }])
    end

    it 'keeps a comparison when one is given' do
      json = build.add_kpi(:resolutions_count, 12, comparison: { previous: 9 }).as_json
      expect(json[:kpis].first[:comparison]).to eq(previous: 9)
    end

    it 'serialises a series as bucket and value pairs' do
      points = [{ bucket: '2026-10-01', value: 1 }, { bucket: '2026-10-02', value: 0 }]
      expect(build.add_series(:volume, points).as_json[:series])
        .to eq([{ key: 'volume', unit: 'count', points: points }])
    end

    it 'serialises a breakdown with its dimension' do
      rows = [{ id: 7, label: 'Support', value: 4 }]
      expect(build.add_breakdown(:by_inbox, :inbox, rows).as_json[:breakdowns])
        .to eq([{ key: 'by_inbox', dimension: 'inbox', unit: 'count', rows: rows }])
    end

    it 'returns the three payload keys even when nothing was added' do
      expect(build.as_json.keys).to eq([:meta, :kpis, :series, :breakdowns])
    end
  end
end
