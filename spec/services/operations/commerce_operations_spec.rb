require 'rails_helper'

RSpec.describe Operations::CommerceOperations do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }

  def store(status: :active, **attributes)
    create(:commerce_store, account: account, status: status, **attributes)
  end

  def health_for(record, **attributes)
    Commerce::StoreHealth.create!(commerce_store_id: record.id, **attributes)
  end

  describe '#summary' do
    # The five counts come from ONE statement, so the tab labels cannot disagree with the lists under them.
    it 'counts connected stores by what an operator would do about each' do
      store(status: :needs_reauth)
      health_for(store, consecutive_failures: 2, last_api_failure_at: Time.current)
      health_for(store, last_api_success_at: (Commerce::StoreHealth::STALE_AFTER + 1.hour).ago)
      store # no snapshot at all
      store(status: :disconnected)

      summary = described_class.new.summary

      expect(summary[:stores]).to eq(4)
      expect(summary[:needs_reauth]).to eq(1)
      expect(summary[:failing]).to eq(1)
      expect(summary[:stale]).to eq(1)
      expect(summary[:unobserved]).to eq(2)
    end

    # A store with a snapshot row that has seen neither an answer nor a failure is as unobserved as one with no
    # row: both mean nobody has called it since recording began.
    it 'counts a snapshot that has observed nothing as unobserved' do
      health_for(store)

      expect(described_class.new.summary[:unobserved]).to eq(1)
    end
  end

  describe 'the views' do
    it 'defaults to what needs a human: a lost authorization or a refusing provider' do
      reauth = store(status: :needs_reauth)
      failing = store
      health_for(failing, consecutive_failures: 1, last_api_failure_at: Time.current)
      store # healthy-but-unobserved, deliberately NOT in the work list

      ids = described_class.new.call[:rows][:entries].map { |row| row[:store].id }

      expect(ids).to contain_exactly(reauth.id, failing.id)
    end

    it 'lists the unobserved stores on their own, because a gap in knowledge is not a job' do
      unobserved = store
      health_for(store(status: :needs_reauth), last_api_success_at: 1.minute.ago)

      result = described_class.new(params: { view: 'unobserved' }).call

      expect(result[:rows][:entries].map { |row| row[:store].id }).to eq([unobserved.id])
    end

    it 'falls back to the default view for a value nobody declared' do
      expect(described_class.new(params: { view: 'everything' }).view).to eq(described_class::DEFAULT_VIEW)
    end
  end

  describe 'each row' do
    it 'reads unknown, not healthy, for a store with no snapshot' do
      store
      row = described_class.new(params: { view: 'all' }).call[:rows][:entries].first

      expect(row[:api_state]).to eq('unknown')
      expect(row[:status]).to eq(Operations::Health::UNKNOWN)
    end

    it 'carries the store\'s last verification from where the connection lifecycle already records it' do
      verified = 3.days.ago
      store(metadata: { 'verified_at' => verified.iso8601 })

      row = described_class.new(params: { view: 'all' }).call[:rows][:entries].first

      expect(row[:verified_at]).to be_within(1.second).of(verified)
    end

    # Through the real transition, which is the only way a production store reaches needs_reauth: the incident
    # is opened by the status CHANGING (Commerce::Store), not by a row being inserted in that state.
    it 'carries the open incident against the store' do
      broken = store
      Commerce::StoreConnection.new(account: account, user: nil).credentials_rejected(broken)

      row = described_class.new.call[:rows][:entries].find { |entry| entry[:store].id == broken.id }

      expect(row[:open_signal]).to eq('critical')
    end
  end

  # Five queries whether the installation has three stores or three thousand.
  it 'does not grow its query count with the number of stores' do
    3.times { store }
    baseline = count_queries { described_class.new(params: { view: 'all' }).call[:rows][:entries].map { |row| row[:api_state] } }

    6.times { store }
    grown = count_queries { described_class.new(params: { view: 'all' }).call[:rows][:entries].map { |row| row[:api_state] } }

    expect(grown).to eq(baseline)
  end

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      count += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
