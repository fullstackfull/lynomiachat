require 'rails_helper'

# The operator work list (docs/product-refinement/07-operations-control-center-v2.md §3).
RSpec.describe Operations::AttentionQueue do
  let(:account) { create(:account, name: 'Hisham Test') }
  let(:other_account) { create(:account, name: 'Another Merchant') }
  let(:inbox) { create(:inbox, account: account) }
  let(:operator) { create(:super_admin) }

  # One recorded signal. `subject:` and `detail:` ride in `extra` so the signature stays short; they vary in
  # only a couple of examples each.
  def record(source:, signal:, severity:, account: nil, **extra)
    Operations::SignalRecorder.new(source: source, account: account, subject: extra[:subject])
                              .record(signal, severity: severity, detail: extra.fetch(:detail, {}))
  end

  describe 'views' do
    let!(:critical) { record(source: :email_channel, signal: :authentication_failed, severity: :critical, account: account, subject: inbox) }
    let!(:warning) { record(source: :webhook, signal: :delivery_failed, severity: :warning, account: other_account) }
    let!(:info) { record(source: :queue, signal: :backlog, severity: :info) }

    it 'defaults to the needs-action view: open, warning or worse, unhandled' do
      queue = described_class.new

      expect(queue.view).to eq('needs_action')
      expect(queue.signals).to contain_exactly(critical, warning)
      expect(queue.signals).not_to include(info)
    end

    it 'ranks worst first, then stalest first inside a severity' do
      stale_warning = record(source: :channel, signal: :connection_failed, severity: :warning, account: account)
      stale_warning.update!(last_seen_at: 3.days.ago)

      expect(described_class.new.signals.to_a).to eq([critical, stale_warning, warning])
    end

    it 'excludes an acknowledged signal from needs-action but keeps it in its own view' do
      Operations::SignalLifecycle.new(signal: critical, actor: operator).acknowledge

      expect(described_class.new.signals).not_to include(critical)
      expect(described_class.new(params: { view: 'acknowledged' }).signals).to contain_exactly(critical)
    end

    it 'excludes a suppressed signal from needs-action and from critical' do
      Operations::SignalLifecycle.new(signal: critical, actor: operator)
                                 .suppress(until_time: 6.hours.from_now, reason: 'Known incident')

      expect(described_class.new.signals).not_to include(critical)
      expect(described_class.new(params: { view: 'critical' }).signals).not_to include(critical)
      expect(described_class.new(params: { view: 'suppressed' }).signals).to contain_exactly(critical)
    end

    it 'falls back to the default view for an unknown one rather than raising' do
      expect(described_class.new(params: { view: 'nonsense' }).view).to eq('needs_action')
    end

    it 'collects recurring signals past the threshold' do
      recorder = Operations::SignalRecorder.new(source: :queue, account: account)
      described_class::RECURRENCE_THRESHOLD.times { recorder.record(:dead_set_grew, severity: :warning) }

      expect(described_class.new(params: { view: 'recurring' }).signals.map(&:signal)).to include('dead_set_grew')
    end
  end

  # The tab counts are one SQL aggregate with FILTER clauses, which duplicates each view's predicate in a
  # second language. A count that disagrees with its own list is worse than a slow page, so they are compared
  # directly.
  describe 'counts' do
    before do
      record(source: :email_channel, signal: :authentication_failed, severity: :critical, account: account, subject: inbox)
      record(source: :webhook, signal: :delivery_failed, severity: :warning, account: other_account)
      record(source: :queue, signal: :backlog, severity: :info)
      suppressed = record(source: :channel, signal: :connection_failed, severity: :critical, account: account)
      Operations::SignalLifecycle.new(signal: suppressed, actor: operator)
                                 .suppress(until_time: 6.hours.from_now, reason: 'Known incident')
      acked = record(source: :commerce_store, signal: :sync_failed, severity: :warning, account: account)
      Operations::SignalLifecycle.new(signal: acked, actor: operator).acknowledge
    end

    it 'agrees with each view it counts' do
      queue = described_class.new
      counts = queue.counts

      described_class::VIEWS.each_key do |name|
        expect(counts[name]).to eq(described_class.new(params: { view: name }).signals.total_count),
                                "count for #{name} disagreed with its own list"
      end
    end
  end

  describe 'filters and search' do
    let!(:imap) do
      record(source: :email_channel, signal: :authentication_failed, severity: :critical,
             account: account, subject: inbox, detail: { code: '5.7.8' })
    end
    let!(:webhook) { record(source: :webhook, signal: :delivery_failed, severity: :warning, account: other_account) }

    it 'filters by severity, source and signal' do
      expect(described_class.new(params: { view: 'all_open', severity: 'critical' }).signals).to contain_exactly(imap)
      expect(described_class.new(params: { view: 'all_open', source: 'webhook' }).signals).to contain_exactly(webhook)
      expect(described_class.new(params: { view: 'all_open', signal: 'delivery_failed' }).signals).to contain_exactly(webhook)
    end

    it 'ignores a filter value that is not on the allow-list rather than returning nothing' do
      expect(described_class.new(params: { view: 'all_open', severity: 'catastrophic' }).signals)
        .to contain_exactly(imap, webhook)
    end

    it 'filters by account' do
      expect(described_class.new(params: { view: 'all_open', account_id: account.id }).signals).to contain_exactly(imap)
    end

    it 'searches by account name' do
      expect(described_class.new(params: { view: 'all_open', q: 'Hisham' }).signals).to contain_exactly(imap)
    end

    it 'searches by signal name' do
      expect(described_class.new(params: { view: 'all_open', q: 'delivery_failed' }).signals).to contain_exactly(webhook)
    end

    # An enhanced status code rather than a bare `535`: the search also matches a term against `account_id`, and
    # account ids here are three digits, so a numeric code collides with whichever account happens to carry it.
    it 'searches by provider error code out of the detail payload' do
      expect(described_class.new(params: { view: 'all_open', q: '5.7.8' }).signals).to contain_exactly(imap)
    end

    it 'searches by account id' do
      expect(described_class.new(params: { view: 'all_open', q: account.id.to_s }).signals).to contain_exactly(imap)
    end

    it 'caps an absurd page size' do
      expect(described_class.new(params: { per_page: 99_999 }).signals.limit_value).to eq(described_class::MAX_PER_PAGE)
    end
  end

  # An operator opening this page on an installation with many signals must not pay per row.
  describe 'query cost' do
    before do
      12.times do |index|
        acc = create(:account, name: "Merchant #{index}")
        record(source: :commerce_store, signal: :sync_failed, severity: :warning, account: acc)
      end
    end

    it 'does not grow with the number of rows' do
      queue = described_class.new(params: { view: 'all_open' })

      statements = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        statements << payload[:sql] unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION])
      end
      begin
        queue.signals.each { |signal| signal.account&.name }
        queue.counts
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      # list + count-for-pagination + preloaded accounts + preloaded support cases + the one counts aggregate.
      expect(statements.size).to be <= 6
    end
  end
end
