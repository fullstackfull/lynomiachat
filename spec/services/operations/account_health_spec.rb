require 'rails_helper'

# The channels column of the operations console. Before P10 it said HEALTHY the moment an account had one inbox,
# whatever state that inbox was in (docs/p10/06-channel-lifecycle-health.md).
RSpec.describe Operations::AccountHealth do
  subject(:channels) do
    row = described_class.new(page: 1, per_page: 100).call[:rows].find { |r| r[:account].id == account.id }
    row[:components].find { |component| component.key == :channels }
  end

  # Eager, because the subject pages through Account.order(:id) and a lazily created account would not be on it.
  let!(:account) { create(:account) }

  def record(inbox, severity:)
    Operations::Signal.create!(account: account, source: 'channel', signal: 'reauthorization_required',
                               subject: inbox, severity: severity, first_seen_at: Time.current,
                               last_seen_at: Time.current)
  end

  context 'with no inbox at all' do
    it 'is unknown, because a half-finished setup is not a fault' do
      expect([channels.status, channels.source_class]).to eq([Operations::Health::UNKNOWN, 'absent'])
      expect(channels.reason).to eq('No inbox is configured')
    end
  end

  context 'with a channel that reports its own health and nothing recorded against it' do
    # The channel factory creates the inbox.
    before { create(:channel_email, account: account) }

    it 'is healthy' do
      expect(channels.status).to eq(Operations::Health::HEALTHY)
      expect(channels.detail).to include(size: 1, broken: 0, flagged: 0)
    end
  end

  context 'with a recorded critical channel problem' do
    let(:inbox) { create(:channel_email, account: account).inbox }

    before { record(inbox, severity: :critical) }

    it 'is critical, and says how many channels cannot connect' do
      expect(channels.status).to eq(Operations::Health::CRITICAL)
      expect(channels.reason).to include('1 channels cannot connect')
      expect(channels.detail).to include(broken: 1)
    end

    it 'counts the inbox once however many problems it has' do
      Operations::Signal.create!(account: account, source: 'channel', signal: 'connection_failed',
                                 subject: inbox, severity: :critical, first_seen_at: Time.current,
                                 last_seen_at: Time.current)

      expect(channels.detail[:broken]).to eq(1)
    end

    it 'stops counting it once the problem is resolved' do
      Operations::Signal.update_all(resolved_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(channels.status).to eq(Operations::Health::HEALTHY)
    end
  end

  context 'with a recorded warning' do
    before { record(create(:channel_email, account: account).inbox, severity: :warning) }

    it 'is a warning, not a failure' do
      expect(channels.status).to eq(Operations::Health::WARNING)
      expect(channels.detail).to include(broken: 0, flagged: 1)
    end
  end

  # P9's rule applied to channels: an area with no source renders `unknown`, because "we have never been told
  # otherwise" and "we checked and it is fine" are different statements.
  context 'with a channel nothing reports on' do
    before { create(:channel_telegram, account: account) }

    it 'is unknown rather than healthy' do
      expect([channels.status, channels.source_class]).to eq([Operations::Health::UNKNOWN, 'absent'])
      expect(channels.reason).to include('do not report whether they are connected')
      expect(channels.detail).to include(unreported: 1)
    end

    it 'keeps the account out of green even when another channel does report' do
      create(:channel_email, account: account)

      expect(channels.status).to eq(Operations::Health::UNKNOWN)
      expect(channels.detail).to include(size: 2, unreported: 1)
    end

    it 'is still critical when something is actually broken' do
      record(create(:channel_email, account: account).inbox, severity: :critical)

      expect(channels.status).to eq(Operations::Health::CRITICAL)
    end
  end

  # A web widget has no provider, so there is nothing for it to be silent about.
  context 'with only a web widget' do
    before { create(:inbox, account: account, channel: create(:channel_widget, account: account)) }

    it 'is healthy' do
      expect(channels.status).to eq(Operations::Health::HEALTHY)
    end
  end

  it 'does not count another account channels' do
    other = create(:account)
    record_inbox = create(:channel_email, account: other).inbox
    Operations::Signal.create!(account: other, source: 'channel', signal: 'reauthorization_required',
                               subject: record_inbox, severity: :critical, first_seen_at: Time.current,
                               last_seen_at: Time.current)
    create(:channel_email, account: account)

    expect(channels.status).to eq(Operations::Health::HEALTHY)
  end
end
