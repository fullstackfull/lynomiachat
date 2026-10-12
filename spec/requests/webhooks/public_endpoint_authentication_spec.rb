require 'rails_helper'

# The completeness sweep behind SC1 (docs/p11/00-p10-security-closure.md). Fixing the Bandwidth webhook raised
# the obvious question of whether the same defect class existed elsewhere, and it did: four more public
# endpoints either had no authentication at all or silently disabled their own check when a secret was
# unconfigured, while taking the receiving tenant from the request body.
#
# One example per endpoint, each written as the request a stranger makes.
RSpec.describe 'public webhook authentication', type: :request do
  include Rails.application.routes.url_helpers

  describe 'Twilio inbound (SEC-1)' do
    let(:channel) do
      create(:channel_twilio_sms, :with_phone_number, account_sid: 'AC777',
                                                      auth_token: 'the-real-token', phone_number: '+15550001111')
    end
    # Built from the channel, so what the forged body names is exactly what a real delivery would name.
    let(:body) do
      { 'From' => '+15559998888', 'To' => channel.phone_number, 'Body' => 'forged',
        'AccountSid' => channel.account_sid }
    end

    it 'refuses a body with no signature, however well it names the channel' do
      expect(Webhooks::TwilioEventsJob).not_to receive(:perform_later)

      post twilio_callback_index_url, params: body

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses a signature computed with a token the caller made up' do
      forged = Twilio::Security::RequestValidator.new('not-the-token')
                                                 .build_signature_for(twilio_callback_index_url, body)

      post twilio_callback_index_url, params: body, headers: { 'HTTP_X_TWILIO_SIGNATURE' => forged }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses a body naming a channel this installation does not have' do
      post twilio_callback_index_url, params: body.merge('AccountSid' => 'AC000', 'To' => '+15550009999'),
                                      headers: { 'HTTP_X_TWILIO_SIGNATURE' => 'anything' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'Twilio delivery status (SEC-2)' do
    let(:channel) do
      create(:channel_twilio_sms, :with_phone_number, account_sid: 'AC778',
                                                      auth_token: 'the-real-token', phone_number: '+15550002222')
    end

    # A forged body here marked an existing outgoing message failed, with an attacker-chosen error string that
    # agents read in the conversation.
    it 'refuses an unsigned status callback' do
      expect(Webhooks::TwilioDeliveryStatusJob).not_to receive(:perform_later)

      post twilio_delivery_status_index_url,
           params: { 'MessageSid' => 'SM1', 'MessageStatus' => 'failed', 'ErrorCode' => '30008',
                     'ErrorMessage' => 'call this number to fix it', 'AccountSid' => channel.account_sid,
                     'From' => channel.phone_number }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'Slack events (SEC-8)' do
    # The tenant came entirely from the body -- an unscoped global lookup on Integrations::Hook#reference_id --
    # and the handler writes an OUTGOING, customer-visible message into that account's conversation. The
    # signature check used to SKIP rather than reject when no secret was configured.
    it 'refuses the delivery when no signing secret is configured, instead of skipping verification' do
      InstallationConfig.where(name: 'SLACK_SIGNING_SECRET').delete_all
      GlobalConfig.clear_cache

      with_modified_env SLACK_SIGNING_SECRET: nil do
        post '/api/v1/integrations/webhooks',
             params: { event: { type: 'message', channel: 'C0FORGED', text: 'forged' } }, as: :json
      end

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses a body with an invalid signature when a secret is configured' do
      with_modified_env SLACK_SIGNING_SECRET: 'slack-signing-secret' do
        post '/api/v1/integrations/webhooks',
             params: { event: { type: 'message', channel: 'C0FORGED', text: 'forged' } },
             headers: { 'X-Slack-Signature' => 'v0=deadbeef', 'X-Slack-Request-Timestamp' => Time.current.to_i.to_s },
             as: :json
      end

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'Facebook Messenger (SEC-5)' do
    # The gem's verifier begins `return unless app_secret_for(...)`, and GlobalConfigService.load answers nil
    # rather than its default for a blank value, so an installation with no FB_APP_SECRET verified nothing.
    it 'never answers a falsy app secret, so the gem cannot skip verification' do
      InstallationConfig.where(name: 'FB_APP_SECRET').delete_all
      GlobalConfig.clear_cache

      with_modified_env FB_APP_SECRET: nil do
        secret = ChatwootFbProvider.new.app_secret_for('any-page-id')

        expect(secret).to be_present
        expect(secret.length).to be >= 32
      end
    end

    it 'answers the configured secret when there is one' do
      with_modified_env FB_APP_SECRET: 'the-real-fb-secret' do
        GlobalConfig.clear_cache
        expect(ChatwootFbProvider.new.app_secret_for('any-page-id')).to eq('the-real-fb-secret')
      end
    end
  end

  describe 'Slack attachment downloads (SEC-9)' do
    let(:account) { create(:account) }
    let(:message) { create(:message, account: account) }
    let(:importer) { Integrations::Slack::AttachmentImporter.new(message: message, access_token: 'xoxb-secret') }

    # url_private comes from the request body and the download carries the account's Slack token, so a URL
    # pointing anywhere else is that token handed to whoever chose it.
    it 'does not send the token to a host the attacker chose' do
      expect(Down::NetHttp).not_to receive(:download)

      importer.import([{ url_private: 'https://attacker.example/steal', mimetype: 'image/png', filetype: 'png' }])

      expect(message.attachments).to be_empty
    end

    it 'does not send the token to a lookalike host' do
      expect(Down::NetHttp).not_to receive(:download)

      importer.import([{ url_private: 'https://files.slack.com.attacker.example/x', mimetype: 'image/png', filetype: 'png' }])
    end

    it 'does not send the token over plain http, or to a url carrying userinfo' do
      expect(Down::NetHttp).not_to receive(:download)

      importer.import([
                        { url_private: 'http://files.slack.com/x', mimetype: 'image/png', filetype: 'png' },
                        { url_private: 'https://user:pass@files.slack.com/x', mimetype: 'image/png', filetype: 'png' }
                      ])
    end

    it 'does send the token to Slack itself' do
      stub_request(:get, 'https://files.slack.com/files-pri/T0A0/ok.png')
        .to_return(status: 200, body: File.read('spec/assets/sample.png'), headers: { 'Content-Type' => 'image/png' })

      expect do
        importer.import([{ url_private: 'https://files.slack.com/files-pri/T0A0/ok.png',
                           mimetype: 'image/png', filetype: 'png' }])
      end.to change { message.attachments.size }.by(1)
    end
  end
end
