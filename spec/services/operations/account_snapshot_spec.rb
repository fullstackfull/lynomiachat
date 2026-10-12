require 'rails_helper'

# Account 360 for operators (docs/product-refinement/07-operations-control-center-v2.md §5).
#
# The product decision behind it: an operator must understand an affected account without hunting through many
# disconnected pages. So what is asserted is that each area is actually present and honest -- including the
# ones that are deliberately "unknown" -- and that the page costs a bounded number of queries.
RSpec.describe Operations::AccountSnapshot do
  subject(:snapshot) { described_class.new(account).call }

  include_context 'with commerce encryption'

  let(:account) { create(:account, name: 'Hisham Test') }
  let(:operator) { create(:super_admin) }

  describe 'identity' do
    it 'reports the account and its agent count' do
      create(:user, account: account, role: :administrator)

      expect(snapshot[:account]).to include(id: account.id, name: 'Hisham Test', status: 'active')
      expect(snapshot[:account][:agents]).to eq(account.account_users.count)
    end

    # The suspension CATEGORY is not a column -- it lives in accounts.internal_attributes['suspensions'].
    # An operator looking at a suspended account needs to know whether it was spam or non-payment, because
    # those are two very different conversations.
    it 'surfaces why an account was suspended' do
      account.update!(status: :suspended,
                      internal_attributes: account.internal_attributes.merge(
                        'suspensions' => [{ 'category' => 'non_payment', 'reason' => 'Card declined twice',
                                            'suspended_at' => Time.current.iso8601 }]
                      ))

      expect(described_class.new(account.reload).call[:account][:suspension])
        .to include('category' => 'non_payment', 'reason' => 'Card declined twice')
    end

    it 'reports no suspension detail for an active account' do
      expect(snapshot[:account][:suspension]).to be_nil
    end
  end

  describe 'commercial state' do
    it 'says so plainly when there is no subscription rather than implying one' do
      expect(snapshot[:commercial]).to eq(subscription: nil, plan: nil, accessible: nil)
    end
  end

  describe 'usage' do
    # A bare count is meaningless until you know the limit, so both are always returned together.
    it 'reports every plan limit key with its usage' do
      expect(snapshot[:usage].keys).to match_array(BillingPlan::LIMIT_KEYS)
      expect(snapshot[:usage]['inboxes']).to have_key(:used)
      expect(snapshot[:usage]['inboxes']).to have_key(:limit)
    end
  end

  describe 'channels' do
    it 'reports whether each channel can report on its own health at all' do
      create(:inbox, account: account, channel: create(:channel_api, account: account))

      channel = snapshot[:channels].first
      expect(channel).to include(:id, :name, :channel_type, :health_reported, :worst_open_signal)
      expect(channel[:health_reported]).to be_in([true, false])
    end

    it 'carries the worst open signal against an inbox' do
      inbox = create(:inbox, account: account)
      Operations::SignalRecorder.new(source: :email_channel, account: account, subject: inbox)
                                .record(:authentication_failed, severity: :critical)

      expect(snapshot[:channels].find { |c| c[:id] == inbox.id }[:worst_open_signal]).to eq('critical')
    end
  end

  describe 'commerce stores' do
    it 'flags a store the merchant must reconnect' do
      create(:commerce_store, account: account, provider: 'shopify', status: :needs_reauth,
                              base_url: 'https://demo.myshopify.com', external_store_id: '1')

      expect(snapshot[:stores].first).to include(provider: 'shopify', status: 'needs_reauth', needs_reauth: true)
    end
  end

  describe 'signals' do
    it 'separates what is open from what still needs a human' do
      handled = Operations::SignalRecorder.new(source: :webhook, account: account)
                                          .record(:delivery_failed, severity: :warning)
      Operations::SignalRecorder.new(source: :queue, account: account).record(:backlog, severity: :critical)
      Operations::SignalLifecycle.new(signal: handled, actor: operator).acknowledge

      expect(snapshot[:signals][:open]).to eq(2)
      expect(snapshot[:signals][:needing_action]).to eq(1)
      expect(snapshot[:signals][:by_severity]).to include('critical' => 1, 'warning' => 1)
    end
  end

  describe 'recent operator activity' do
    it 'shows what Lynomia operators recently did about this account' do
      signal = Operations::SignalRecorder.new(source: :queue, account: account).record(:backlog, severity: :warning)
      Operations::SignalLifecycle.new(signal: signal, actor: operator).acknowledge(reason: 'Investigating')

      activity = described_class.new(account).call[:recent_operator_activity]
      expect(activity.map(&:event_type)).to include('acknowledged')
      expect(activity.first.reason).to eq('Investigating')
    end

    it "does not show another account's operator activity" do
      other = create(:account)
      signal = Operations::SignalRecorder.new(source: :queue, account: other).record(:backlog, severity: :warning)
      Operations::SignalLifecycle.new(signal: signal, actor: operator).acknowledge

      expect(described_class.new(account).call[:recent_operator_activity]).to be_empty
    end
  end

  # A detail page may afford more than a list, but it must not be unbounded: an account with many inboxes,
  # stores and signals has to cost the same as a small one.
  describe 'query cost' do
    it 'does not grow with how much the account has' do
      5.times { create(:inbox, account: account) }
      3.times do |index|
        create(:commerce_store, account: account, provider: 'woocommerce', status: :active,
                                base_url: "https://shop#{index}.example.com", external_store_id: "w#{index}")
      end
      4.times do |i|
        Operations::SignalRecorder.new(source: :webhook, account: account).record(:delivery_failed, severity: :warning, detail: { attempts: i })
      end

      counts = []
      2.times do |run|
        statements = []
        subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
          statements << payload[:sql] unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION])
        end
        begin
          described_class.new(account.reload).call
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end
        counts << statements.size
        next unless run.zero?

        # grow the account between the two runs
        5.times { create(:inbox, account: account) }
        4.times do |i|
          Operations::SignalRecorder.new(source: :channel, account: account).record(:connection_failed, severity: :warning, detail: { strikes: i })
        end
      end

      expect(counts.last).to eq(counts.first)
    end
  end
end
