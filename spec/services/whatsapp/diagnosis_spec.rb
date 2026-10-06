require 'rails_helper'

# The operator-facing diagnostic (docs/real-whatsapp-uat/10-real-uat-results.md). Its value depends entirely on
# three promises, so each one is pinned here: it reports the seven sections, it writes nothing anywhere, and it
# never prints a credential or a customer's full number.
RSpec.describe Whatsapp::Diagnosis do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              provider_config: { 'webhook_verify_token' => 'verify-me' },
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:report) { described_class.new(inbox_id: inbox.id).run }

  before do
    stub_request(:get, /graph\.facebook\.com/)
      .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'reports the seven sections an operator reads down, in order' do
    headings = ['CHANNEL', 'META IDENTITY', 'AUTH', 'WABA SUBSCRIPTION', 'WEBHOOK', 'LOCAL PIPELINE', 'CONTACT TEST']
    positions = headings.map { |heading| report.index("#{heading} — inbox ##{inbox.id}") }

    expect(positions).to all(be_present)
    expect(positions).to eq(positions.sort)
  end

  it 'ends with a summary and a prioritised fix order' do
    expect(report).to include('SUMMARY')
    expect(report).to match(/\d+ passed, \d+ failed, \d+ blocked/)
  end

  it 'reads from Meta with GETs only' do
    report

    expect(WebMock).to have_requested(:get, /graph\.facebook\.com/).at_least_once
    %i[post put patch delete].each do |verb|
      expect(WebMock).not_to have_requested(verb, /graph\.facebook\.com/)
    end
  end

  it 'writes nothing to the database' do
    channel
    counts = -> { [Message.count, Contact.count, Conversation.count, Channel::Whatsapp.count, Inbox.count] }
    before_counts = counts.call

    report

    expect(counts.call).to eq(before_counts)
    expect(channel.reload.provider_config).to eq(channel.provider_config)
  end

  # The regressions for the defect this spec's first version missed, and for the one real write that remains.
  #
  # GlobalConfigService.load ends in `InstallationConfig.where(name:).first_or_create` plus
  # `GlobalConfig.clear_cache`, so every key the diagnosis read through it was a potential INSERT. On a server
  # where WHATSAPP_APP_SECRET is set in ENV but has no row, the diagnosis would have written the app secret into
  # the database. Reading configuration must not write it, least of all a credential —
  # Whatsapp::Diagnosis::StoredConfig is now the one place that reads, with a plain SELECT.
  describe 'what it may and may not write to installation_configs' do
    let(:secret_keys) do
      %w[WHATSAPP_APP_SECRET WHATSAPP_APP_ID WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN INSTALLATION_NAME
         INACTIVE_WHATSAPP_NUMBERS]
    end

    before { channel }

    it 'never creates a row for a key it reads, even when ENV supplies a value' do
      InstallationConfig.where(name: secret_keys).delete_all

      with_modified_env WHATSAPP_APP_SECRET: 'a-real-secret', WHATSAPP_APP_ID: '123', INSTALLATION_NAME: 'Lynomia' do
        report
      end

      expect(InstallationConfig.where(name: secret_keys)).to be_empty
    end

    it 'never writes a credential into the database' do
      with_modified_env WHATSAPP_APP_SECRET: 'a-real-secret' do
        report
      end

      expect(InstallationConfig.pluck(:name)).not_to include('WHATSAPP_APP_SECRET')
    end

    # The one row a run can add, and it is not the diagnosis's own doing: nine production call sites resolve the
    # Graph version through GlobalConfigService.load, Whatsapp::FacebookApiClient#initialize among them
    # (app/services/whatsapp/facebook_api_client.rb:13), so the first WhatsApp request of any kind on that server
    # creates the same row with the same value. It holds a version string, never a credential. This example
    # exists so that the set can never widen unnoticed.
    it 'adds at most the Graph version row, created by the installation own API client' do
      before_names = InstallationConfig.pluck(:name)

      report

      expect(InstallationConfig.pluck(:name) - before_names).to all(eq('WHATSAPP_API_VERSION'))
    end

    it 'reports a stored value and an ENV fallback without writing either' do
      create(:installation_config, name: 'WHATSAPP_APP_ID', value: 'stored-app-id', locked: false)

      with_modified_env WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN: 'env-verify-token' do
        expect(report).to include('stored-app-id')
      end

      expect(InstallationConfig.find_by(name: 'WHATSAPP_APP_WEBHOOK_VERIFY_TOKEN')).to be_nil
    end
  end

  it 'writes nothing to Redis' do
    channel
    allow(Redis::Alfred).to receive(:set).and_call_original
    allow(Redis::Alfred).to receive(:delete).and_call_original
    allow(Redis::Alfred).to receive(:incr).and_call_original

    report

    expect(Redis::Alfred).not_to have_received(:set)
    expect(Redis::Alfred).not_to have_received(:delete)
    expect(Redis::Alfred).not_to have_received(:incr)
  end

  it 'does not clear or set an existing reauthorization flag' do
    channel.prompt_reauthorization!

    report

    expect(channel.reauthorization_required?).to be true
    expect(report).to include('REAUTHORIZATION REQUIRED')
  end

  it 'never prints a credential value, and reports presence instead' do
    expect(report).not_to include(channel.provider_config['api_key'])
    expect(report).not_to include('verify-me')
    expect(report).to include('access token (provider_config.api_key): present')
  end

  it 'never prints a phone number in full' do
    expect(report).not_to include(channel.phone_number)
    expect(report).to include(channel.phone_number[0, 5])
  end

  it 'says plainly that it has no channel to diagnose rather than guessing' do
    Message.delete_all
    Inbox.delete_all
    Channel::Whatsapp.delete_all

    expect(described_class.new.run).to include('NO WHATSAPP CHANNEL FOUND')
  end
end
