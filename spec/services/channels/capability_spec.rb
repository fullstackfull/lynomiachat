require 'rails_helper'

# The table is only worth having if it is complete and if every row is a repository fact
# (docs/p10/02-channel-capability-matrix.md). Both are asserted here rather than reviewed by eye.
RSpec.describe Channels::Capability do
  # Every Channel:: model in the fork, read from the filesystem so a channel added later fails this rather than
  # quietly getting no entry -- which is the case that would render as `unknown` for ever.
  let(:channel_models) do
    Dir[Rails.root.join('app/models/channel/*.rb')].map { |path| "Channel::#{File.basename(path, '.rb').camelize}" }
  end

  it 'describes every channel this fork has, and nothing it does not' do
    expect(described_class::BY_CHANNEL_TYPE.keys).to match_array(channel_models)
  end

  it 'uses only the declared identities, connections and health sources' do
    described_class::ENTRIES.each do |entry|
      expect(described_class::IDENTITIES).to include(entry.identity)
      expect(described_class::CONNECTIONS).to include(entry.connection)
      expect(described_class::HEALTH_SOURCES).to include(*entry.health_sources) if entry.health_sources.any?
    end
  end

  it 'gives every channel a distinct key' do
    keys = described_class::ENTRIES.map(&:key)

    expect(keys.uniq.length).to eq(keys.length)
  end

  describe 'health_sources, against the code that would write them' do
    # reauth_latch means the channel class includes Reauthorizable. Anything else is a claim the repository does
    # not support.
    it 'claims a reauthorization latch only for channels that include Reauthorizable' do
      latching = described_class::ENTRIES.select { |entry| entry.health_source?(:reauth_latch) }.map(&:channel_type)
      actually_latch = channel_models.select { |name| name.constantize.include?(Reauthorizable) }

      expect(latching).to match_array(actually_latch)
    end

    it 'claims a token expiry only for channels whose row stores one' do
      expiring = described_class::ENTRIES.select { |entry| entry.health_source?(:token_expiry) }.map(&:channel_type)

      expect(expiring).to match_array(
        channel_models.select { |name| name.constantize.column_names.include?('expires_at') }
      )
    end

    it 'claims provider health only for the channel whose row stores it' do
      reporting = described_class::ENTRIES.select { |entry| entry.health_source?(:provider_health) }.map(&:channel_type)

      expect(reporting).to eq(['Channel::Whatsapp'])
      expect(Channel::Whatsapp.column_names).to include('phone_number_health')
    end
  end

  it 'treats only the two channels with no external provider as unbacked' do
    expect(described_class::ENTRIES.reject(&:provider_backed?).map(&:key)).to contain_exactly(:website, :api)
  end

  it 'returns nothing for a channel type it does not know, rather than a default' do
    expect(described_class.for_channel_type('Channel::Pigeon')).to be_nil
  end

  it 'answers for an inbox' do
    inbox = create(:inbox, channel: create(:channel_widget))

    expect(described_class.identity_of(inbox)).to eq(:anonymous)
  end
end
