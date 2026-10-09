require 'rails_helper'

RSpec.describe Analytics::DateRange do
  let(:account) { create(:account, reporting_timezone: 'Asia/Kuwait') }

  def build(since: '2026-10-01', until_value: '2026-10-07', group_by: nil, for_account: account)
    described_class.new(account: for_account, since: since, until_value: until_value, group_by: group_by)
  end

  describe 'timezone resolution' do
    it 'uses the account reporting timezone' do
      expect(build.zone).to eq('Asia/Kuwait')
    end

    it 'falls back to UTC when the account has none, matching TimezoneHelper#timezone_name_from_offset' do
      expect(build(for_account: create(:account)).zone).to eq('UTC')
    end

    it 'falls back to UTC for a stored value that is not a real zone' do
      # Account validates this on write, so a row holding an invalid zone can only predate the validation.
      account.reporting_timezone = 'Invalid/Zone'
      account.save(validate: false)
      expect(build(for_account: account.reload).zone).to eq('UTC')
    end
  end

  describe 'UTC boundaries' do
    it 'starts at the account midnight expressed in UTC' do
      # Asia/Kuwait is UTC+3 all year, so 1 Oct 00:00 local is 30 Sep 21:00 UTC.
      expect(build.starts_at).to eq(Time.utc(2026, 9, 30, 21, 0, 0))
    end

    it 'ends at the start of the day after `until`, so `until` is an inclusive date' do
      expect(build.ends_at).to eq(Time.utc(2026, 10, 7, 21, 0, 0))
    end

    it 'is half-open, so adjacent ranges neither double count nor skip an instant' do
      first = build(since: '2026-10-01', until_value: '2026-10-03')
      second = build(since: '2026-10-04', until_value: '2026-10-06')

      expect(first.ends_at).to eq(second.starts_at)
      expect(first.utc_range.exclude_end?).to be(true)
      expect(first.utc_range).not_to cover(first.ends_at)
      expect(second.utc_range).to cover(second.starts_at)
    end

    it 'places an instant near local midnight in the account day, not the UTC day' do
      # 1 Oct 22:00 UTC is 2 Oct 01:00 in Kuwait.
      instant = Time.utc(2026, 10, 1, 22, 0, 0)
      october_second = build(since: '2026-10-02', until_value: '2026-10-02')
      october_first = build(since: '2026-10-01', until_value: '2026-10-01')

      expect(october_second.utc_range).to cover(instant)
      expect(october_first.utc_range).not_to cover(instant)
    end
  end

  describe 'daylight saving' do
    let(:dst_account) { create(:account, reporting_timezone: 'America/New_York') }

    it 'uses the offset in force on each boundary rather than a fixed one' do
      # New York leaves DST on 1 November 2026: 25 Oct is UTC-4, 5 Nov is UTC-5.
      range = build(since: '2026-10-25', until_value: '2026-11-05', for_account: dst_account)

      expect(range.starts_at).to eq(Time.utc(2026, 10, 25, 4, 0, 0))
      expect(range.ends_at).to eq(Time.utc(2026, 11, 6, 5, 0, 0))
    end

    it 'still produces one bucket per calendar day across the transition' do
      range = build(since: '2026-10-25', until_value: '2026-11-05', for_account: dst_account)
      expect(range.bucket_count).to eq(12)
    end
  end

  describe 'determinism independent of the viewer' do
    it 'resolves identically whatever request timezone the viewer is in' do
      results = ['UTC', 'Asia/Tokyo', 'America/Los_Angeles'].map do |viewer_zone|
        Time.use_zone(viewer_zone) { build.to_meta }
      end

      expect(results.uniq.length).to eq(1)
      expect(results.first[:timezone]).to eq('Asia/Kuwait')
    end

    it 'resolves the same UTC window whatever request timezone the viewer is in' do
      windows = ['UTC', 'Pacific/Auckland', 'America/Sao_Paulo'].map do |viewer_zone|
        Time.use_zone(viewer_zone) { [build.starts_at, build.ends_at] }
      end

      expect(windows.uniq.length).to eq(1)
    end
  end

  describe 'buckets' do
    it 'emits one bucket per day' do
      expect(build.bucket_count).to eq(7)
    end

    it 'truncates weekly buckets to the start of the week' do
      range = build(since: '2026-10-01', until_value: '2026-10-21', group_by: 'week')
      expect(range.bucket_starts.map { |bucket| bucket.strftime('%Y-%m-%d') })
        .to eq(%w[2026-09-28 2026-10-05 2026-10-12 2026-10-19])
    end

    it 'truncates monthly buckets to the start of the month' do
      range = build(since: '2026-02-15', until_value: '2026-04-02', group_by: 'month')
      expect(range.bucket_starts.map { |bucket| bucket.strftime('%Y-%m-%d') })
        .to eq(%w[2026-02-01 2026-03-01 2026-04-01])
    end

    it 'builds bucket starts in the account timezone' do
      expect(build.bucket_starts.first.time_zone.name).to eq('Asia/Kuwait')
    end
  end

  describe 'validation' do
    it 'rejects a missing since' do
      expect { build(since: nil) }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::MissingDate') })
    end

    it 'rejects a missing until' do
      expect { build(until_value: '') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::MissingDate') })
    end

    it 'rejects a date that is not YYYY-MM-DD' do
      expect { build(since: '01/10/2026') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::InvalidDate') })
    end

    it 'rejects an epoch timestamp, because the contract is calendar dates' do
      expect { build(since: '1759276800') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::InvalidDate') })
    end

    it 'rejects a date that does not exist' do
      expect { build(since: '2026-02-30') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::InvalidDate') })
    end

    it 'rejects an inverted range' do
      expect { build(since: '2026-10-08', until_value: '2026-10-01') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::InvertedRange') })
    end

    it 'accepts a single day' do
      expect(build(since: '2026-10-01', until_value: '2026-10-01').bucket_count).to eq(1)
    end

    it 'rejects an unsupported group_by' do
      expect { build(group_by: 'fortnight') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::InvalidGroupBy') })
    end

    it 'rejects hour and year, which the P8 contract does not yet accept' do
      %w[hour year].each do |group_by|
        expect { build(group_by: group_by) }
          .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::InvalidGroupBy') })
      end
    end

    it 'defaults group_by to day' do
      expect(build.group_by).to eq('day')
    end

    it 'rejects a range wider than the daily bucket ceiling' do
      expect { build(since: '2024-01-01', until_value: '2026-10-07') }
        .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::Analytics::RangeTooLarge') })
    end

    it 'accepts that same wide range when grouped by month' do
      expect(build(since: '2024-01-01', until_value: '2026-10-07', group_by: 'month').bucket_count).to eq(34)
    end
  end

  describe '#to_meta' do
    it 'reports the timezone, the resolved instants and the boundary semantics' do
      expect(build.to_meta).to include(
        since: '2026-10-01', until: '2026-10-07', group_by: 'day', timezone: 'Asia/Kuwait',
        starts_at: '2026-09-30T21:00:00Z', ends_at: '2026-10-07T21:00:00Z',
        boundaries: 'start inclusive, end exclusive'
      )
    end
  end
end
