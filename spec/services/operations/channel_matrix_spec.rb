require 'rails_helper'

RSpec.describe Operations::ChannelMatrix do
  let(:account) { create(:account) }

  def row_for(key) = described_class.new.rows.find { |row| row[:entry].key == key }

  # The rule this page exists to enforce. Nothing in this fork reports whether a Telegram connection still
  # works, so a quiet Telegram inbox must read unknown however long it has been quiet.
  it 'reads unknown for a channel type with no health source, however quiet it is' do
    create(:channel_telegram, account: account)

    row = row_for(:telegram)

    expect(row[:inboxes]).to eq(1)
    expect(row[:component].status).to eq(Operations::Health::UNKNOWN)
    expect(row[:component].source_class).to eq('absent')
    expect(row[:component].reason).to eq('Nothing in this installation reports whether this connection still works')
  end

  it 'reads unknown for a channel with no provider to stay connected to' do
    create(:channel_api, account: account)

    expect(row_for(:api)[:component].reason).to eq('This channel has no external provider to stay connected to')
  end

  it 'says nothing at all about a channel type nobody uses' do
    expect(row_for(:line)[:component].reason).to eq('No inbox of this type exists')
  end

  describe 'a channel type with real evidence' do
    let!(:whatsapp) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    end

    it 'may read healthy, and names the evidence it has' do
      row = row_for(:whatsapp)

      expect(row[:component].status).to eq(Operations::Health::HEALTHY)
      expect(row[:component].detail[:evidence]).to eq('reauth_latch,provider_health')
    end

    it 'reads critical once something is recorded against one of its inboxes' do
      Operations::SignalRecorder.new(source: :channel, account: account, subject: whatsapp.inbox)
                                .record(:reauthorization_required, severity: :critical)

      row = row_for(:whatsapp)

      expect(row[:component].status).to eq(Operations::Health::CRITICAL)
      expect(row[:affected]).to eq(1)
      expect(row[:component].reason).to eq('1 of 1 inboxes reported a problem')
    end
  end

  it 'lists the channel types this installation can say nothing about' do
    expect(described_class.new.unreported).to contain_exactly(:website, :api, :telegram, :line, :twilio, :sms, :twitter)
  end

  it 'reports only the channel types something is recorded against as degraded' do
    inbox = create(:channel_email, account: account).inbox
    Operations::SignalRecorder.new(source: :email_channel, account: account, subject: inbox)
                              .record(:authentication_failed, severity: :critical)

    expect(described_class.new.degraded.map { |row| row[:entry].key }).to eq([:email])
  end

  # Two queries for the aggregate, whatever the installation holds: the per-inbox live answer is deliberately
  # not called here (Channels::ConnectionState says not to, across accounts).
  it 'does not grow its query count with the number of inboxes' do
    3.times { create(:channel_api, account: account) }
    baseline = count_queries { described_class.new.rows }

    6.times { create(:channel_api, account: account) }
    grown = count_queries { described_class.new.rows }

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
