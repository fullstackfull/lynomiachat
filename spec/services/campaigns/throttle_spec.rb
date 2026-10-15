require 'rails_helper'

# A campaign was one loop with no ceiling, sending as fast as the provider would accept
# connections -- which is how a WhatsApp sender earns a rate-limit response, a quality-rating
# drop and eventually a lower messaging tier. The rating and tier were already being fetched
# and displayed, and read by nothing that could slow a send down.
RSpec.describe Campaigns::Throttle do
  let(:account) { create(:account) }
  # Injected so the examples assert the pause instead of taking it; a spec that really slept
  # would be slow and would still not prove when it slept.
  let(:paused) { [] }
  let(:sleeper) { ->(seconds) { paused << seconds } }

  before { Redis::Alfred.delete(described_class.key(account)) }

  it 'lets a send through while the account is under its ceiling' do
    described_class.pace(account, sleeper: sleeper)

    expect(paused).to be_empty
    expect(described_class.used(account)).to eq(1)
  end

  it 'counts each send against the current second' do
    3.times { described_class.pace(account, sleeper: sleeper) }

    expect(described_class.used(account)).to eq(3)
  end

  # PACES RATHER THAN REFUSES. A refusal would mean the recipients at the END of a large
  # audience silently never hear from the merchant -- worse than a slow send, and far harder
  # to notice.
  it 'waits at the ceiling instead of dropping the recipient' do
    account.update!(settings: account.settings.merge(described_class::SETTING_KEY => 2))
    2.times { described_class.pace(account, sleeper: sleeper) }

    expect(described_class.pace(account, sleeper: sleeper)).to be(true)
    expect(paused).not_to be_empty
  end

  it 'never blocks a worker for longer than its own ceiling on waiting' do
    account.update!(settings: account.settings.merge(described_class::SETTING_KEY => 1))
    described_class.pace(account, sleeper: sleeper)

    described_class.pace(account, sleeper: sleeper)

    expect(paused.sum).to be <= described_class::MAX_WAIT + 0.11
  end

  describe 'the ceiling' do
    it 'defaults when the account says nothing' do
      expect(described_class.ceiling_for(account)).to eq(described_class::DEFAULT_PER_SECOND)
    end

    it 'follows an operator setting' do
      account.update!(settings: account.settings.merge(described_class::SETTING_KEY => 25))

      expect(described_class.ceiling_for(account)).to eq(25)
    end

    # The escape hatch for a migration or a load test, not a setting to leave on.
    it 'is off entirely at zero, and then nothing is counted' do
      account.update!(settings: account.settings.merge(described_class::SETTING_KEY => 0))

      described_class.pace(account, sleeper: sleeper)

      expect(paused).to be_empty
      expect(described_class.used(account)).to eq(0)
    end
  end

  # The window IS the key, so a second's counter expires with that second. Without this the
  # expiry would be pushed forward by every send and a one-second window would become a
  # rolling one that never resets under load.
  it 'starts a fresh window each second' do
    described_class.pace(account, sleeper: sleeper)
    first = described_class.key(account)

    travel_to(2.seconds.from_now) do
      expect(described_class.key(account)).not_to eq(first)
      expect(described_class.used(account)).to eq(0)
    end
  end

  # A ceiling is protection against sending too fast, not authorization to send at all --
  # that is consent, and consent fails closed elsewhere. A cache blip must not become an
  # outage.
  it 'lets the send through when Redis cannot be read' do
    allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError)

    expect(described_class.pace(account, sleeper: sleeper)).to be(true)
  end

  # Verified in the real loop, not only against the module: a throttle nothing calls is a
  # throttle that does not exist.
  describe 'in the WhatsApp sender' do
    let!(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                validate_provider_config: false, sync_templates: false)
    end
    let(:campaign) do
      create(:campaign, inbox: channel.inbox, account: account, campaign_type: :one_off,
                        template_params: { 'name' => 't', 'category' => 'UTILITY', 'language' => 'en',
                                           'processed_params' => { 'body' => {} } })
    end

    before do
      account.enable_features!(:whatsapp_campaign)
      stub_request(:post, /graph\.facebook\.com.*messages/)
        .to_return(status: 200, body: { messages: [{ id: 'm1' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      allow_any_instance_of(Whatsapp::OneoffCampaignService).to receive(:channel).and_return(channel) # rubocop:disable RSpec/AnyInstance
    end

    it 'paces every recipient it actually sends to' do
      contacts = create_list(:contact, 3, :with_phone_number, account: account)
      allow(campaign).to receive(:audience_contacts).and_return(contacts)
      allow(described_class).to receive(:pace).and_call_original

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(described_class).to have_received(:pace).exactly(3).times
    end
  end
end
