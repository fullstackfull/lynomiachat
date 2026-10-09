require 'rails_helper'

# What the dashboard is told about a channel's connection (docs/p10/06-channel-lifecycle-health.md).
#
# Two of these are regressions of real silent-green cases: a plain IMAP inbox and a manually configured WhatsApp
# number both latch reauthorization, and neither used to say so to anybody.
RSpec.describe 'Inbox connection state', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def inbox_payload(inbox, as:)
    get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: as.create_new_auth_token, as: :json
    response.parsed_body
  end

  describe 'connection_state' do
    it 'is reported for a channel that has no provider, as unknown rather than as nothing' do
      inbox = create(:inbox, account: account, channel: create(:channel_widget, account: account))

      state = inbox_payload(inbox, as: administrator)['connection_state']

      expect(state).to include('key' => 'connection', 'status' => 'unknown', 'source_class' => 'absent')
      expect(state['reason']).to include('no external provider')
    end

    it 'is reported for a channel nothing reports on' do
      inbox = create(:channel_telegram, account: account).inbox

      expect(inbox_payload(inbox, as: administrator)['connection_state']['status']).to eq('unknown')
    end

    it 'is reported to an agent as well as to an administrator' do
      inbox = create(:channel_telegram, account: account).inbox
      create(:inbox_member, user: agent, inbox: inbox)

      expect(inbox_payload(inbox, as: agent)['connection_state']).to be_present
    end
  end

  describe 'a plain IMAP email inbox that can no longer authenticate' do
    let(:inbox) { create(:channel_email, account: account).inbox }

    before { inbox.channel.prompt_reauthorization! }

    it 'says so, where it used to say nothing because the inbox was not a Google or Microsoft one' do
      expect(inbox_payload(inbox, as: administrator)['reauthorization_required']).to be(true)
    end

    it 'says so to an agent, who is the one looking at the sidebar' do
      create(:inbox_member, user: agent, inbox: inbox)

      expect(inbox_payload(inbox, as: agent)['reauthorization_required']).to be(true)
    end

    it 'reports it as the connection state too' do
      expect(inbox_payload(inbox, as: administrator)['connection_state']['status']).to eq('critical')
    end
  end

  describe 'a manually configured WhatsApp number that can no longer authenticate' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                provider_config: { 'api_key' => 'k', 'phone_number_id' => '1',
                                                   'business_account_id' => '2', 'source' => 'manual_setup_v2' },
                                sync_templates: false, validate_provider_config: false)
    end

    before { channel.prompt_reauthorization! }

    it 'says so, where it used to report only embedded-signup numbers' do
      expect(inbox_payload(channel.inbox, as: administrator)['reauthorization_required']).to be(true)
    end

    it 'does not pretend an embedded-signup reconnect is available' do
      payload = inbox_payload(channel.inbox, as: administrator)

      expect(payload['provider_config']['source']).to eq('manual_setup_v2')
    end
  end
end
