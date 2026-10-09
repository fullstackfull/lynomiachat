require 'rails_helper'

RSpec.describe Operations::Signal do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def build_signal(**attributes)
    described_class.new({ source: 'email_channel', signal: 'authentication_failed', severity: :critical,
                          account: account, subject: inbox, first_seen_at: 1.hour.ago,
                          last_seen_at: 1.minute.ago }.merge(attributes))
  end

  describe 'allow-lists' do
    it 'refuses a source, a signal or a subject type outside its list' do
      expect(build_signal(source: 'telepathy')).not_to be_valid
      expect(build_signal(signal: 'everything_broke')).not_to be_valid
      expect(build_signal(subject_type: 'User', subject_id: 1)).not_to be_valid
    end

    it 'accepts every listed value' do
      described_class::SOURCES.each { |source| expect(build_signal(source: source)).to be_valid }
      described_class::SIGNALS.each { |signal| expect(build_signal(signal: signal)).to be_valid }
    end
  end

  it 'allows an installation-wide signal with no account and no subject' do
    expect(build_signal(account: nil, subject: nil, source: 'queue', signal: 'no_workers')).to be_valid
  end

  describe 'the open identity' do
    # Mirrors the partial unique index, which is what the dedup and the case bridge both rely on.
    it 'treats a missing account and a missing subject as zero rather than as distinct' do
      queue = build_signal(account: nil, subject: nil, source: 'queue', signal: 'backlog')

      expect(queue.identity).to eq([0, 'queue', '', 0, 'backlog'])
    end

    it 'refuses a second open row for the same problem at the database level' do
      build_signal.save!

      expect { build_signal.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows a second row once the first is resolved' do
      build_signal(resolved_at: 1.minute.ago).save!

      expect { build_signal.save! }.not_to raise_error
    end
  end

  describe 'scopes' do
    it 'separates open from resolved and finds the ones needing attention' do
      open_critical = build_signal.tap(&:save!)
      build_signal(signal: 'connection_failed', severity: :info).save!
      resolved = build_signal(signal: 'reauthorization_required', resolved_at: 1.minute.ago).tap(&:save!)

      expect(described_class.open_signals.count).to eq(2)
      expect(described_class.resolved).to contain_exactly(resolved)
      expect(described_class.needing_attention).to contain_exactly(open_critical)
    end
  end
end
