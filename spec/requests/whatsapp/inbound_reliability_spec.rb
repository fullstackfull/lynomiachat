require 'rails_helper'

# P5 continuation (docs/real-whatsapp-uat/09-fix.md): the regressions for the inbound-reliability defects.
#
# Each example pins a behaviour that was wrong and is now right, so the way back in is a failing test rather than
# another production outage. Where an earlier spec asserted the defect, the replacement lives beside the original
# (spec/jobs/webhooks/whatsapp_events_job_spec.rb, spec/services/whatsapp/embedded_signup_service_spec.rb) and is
# referenced here rather than duplicated.
RSpec.describe 'WhatsApp inbound reliability', type: :request do
  let(:account) { create(:account) }
  # Channel::Whatsapp enforces global phone_number uniqueness, so the factory's sequence owns the number rather
  # than this spec hardcoding one a neighbouring spec could already hold. The factory also merges its own
  # provider_config defaults OVER whatever is passed, so the payload below reads the ids back off the channel
  # instead of asserting what they were asked to be.
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              provider_config: { 'webhook_verify_token' => 'verify-me' },
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:phone_number_id) { channel.provider_config['phone_number_id'] }

  # The controller hands the job `params.to_unsafe_hash`, which is indifferent-access: `processed_params` reads
  # string keys while the handlers read symbols, so a plain symbol-keyed hash would silently resolve to nothing.
  let(:message_payload) do
    {
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          field: 'messages',
          value: {
            metadata: { display_phone_number: channel.phone_number.delete('+'), phone_number_id: phone_number_id },
            contacts: [{ profile: { name: 'Jane' }, wa_id: '15559998888' }],
            messages: [{ from: '15559998888', id: 'wamid.TEST1', timestamp: '1700000000',
                         text: { body: 'Hello' }, type: 'text' }]
          }
        }]
      }]
    }.with_indifferent_access
  end

  describe 'the reauthorization latch no longer costs customer messages' do
    # Required test 3 and 4. The guard used to discard this payload outright.
    it 'persists an inbound text message on a channel awaiting reauthorization' do
      channel.prompt_reauthorization!
      expect(channel.reauthorization_required?).to be true

      expect { Webhooks::WhatsappEventsJob.perform_now(message_payload.deep_dup) }
        .to change { inbox.messages.incoming.count }.by(1)

      message = inbox.messages.incoming.last
      expect(message.content).to eq('Hello')
      expect(message.source_id).to eq('wamid.TEST1')
    end

    # Required test 19: the persisted inbound message is what opens the reply window, which is the whole reason
    # dropping it also broke outbound to new contacts.
    it 'opens reply eligibility for the conversation it creates' do
      channel.prompt_reauthorization!
      Webhooks::WhatsappEventsJob.perform_now(message_payload.deep_dup)

      conversation = inbox.conversations.last
      expect(conversation).to be_present
      expect(Conversations::MessageWindowService.new(conversation).can_reply?).to be true
    end

    # Required test 6 and 11: a channel with no inbound message has a closed window, and that is what the send
    # path refuses on — not a Meta rejection.
    it 'leaves a conversation with no inbound message outside the window' do
      conversation = create(:conversation, inbox: inbox, account: account)
      expect(Conversations::MessageWindowService.new(conversation).can_reply?).to be false
    end
  end

  describe 'a dropped payload is observable' do
    # Required test 3: the refusals that remain must not be one bare warning line.
    it 'reports an unroutable payload with the phone_number_id it could not match' do
      allow(Rails.logger).to receive(:error)
      payload = message_payload.deep_dup
      payload[:entry][0][:changes][0][:value][:metadata][:phone_number_id] = '999000'

      expect(Rails.logger).to receive(:error).with(
        a_string_including('[WHATSAPP INGEST] event=unroutable_payload', 'phone_number_id=999000')
      )
      expect { Webhooks::WhatsappEventsJob.perform_now(payload) }.not_to(change(Message, :count))
    end

    it 'reports a suspended account rather than failing silently' do
      channel
      account.update!(status: :suspended)
      allow(Rails.logger).to receive(:error)

      expect(Rails.logger).to receive(:error).with(
        a_string_including('[WHATSAPP INGEST] event=inactive_account', "channel_id=#{channel.id}")
      )
      Webhooks::WhatsappEventsJob.perform_now(message_payload.deep_dup)
    end
  end

  describe 'the dedup lock' do
    let(:lock_key) { format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: 'wamid.TEST1') }

    after { Redis::Alfred.delete(lock_key) }

    # Required test 11.
    it 'is released once the message is persisted' do
      Webhooks::WhatsappEventsJob.perform_now(message_payload.deep_dup)

      expect(inbox.messages.incoming.count).to eq(1)
      expect(Redis::Alfred.get(lock_key)).to be_nil
    end

    # Ingestion is made to fail at the first durable step after the lock is taken. Stubbing the resolver class is
    # how the real failure arrives too: a timeout or a validation error inside contact resolution.
    def fail_contact_resolution!
      allow(ContactInboxSourceIdResolver).to receive(:new).and_raise(StandardError, 'boom')
    end

    # Required test 12: the defect. One failure used to leave the id locked for a day, so every redelivery from
    # Meta was discarded and the message was lost with no trace.
    it 'is released when ingestion raises, so a redelivery can still succeed' do
      fail_contact_resolution!

      expect { Webhooks::WhatsappEventsJob.perform_now(message_payload.deep_dup) }.to raise_error('boom')
      expect(Redis::Alfred.get(lock_key)).to be_nil
    end

    it 'lets Meta\'s redelivery succeed after a failed attempt' do
      fail_contact_resolution!
      expect { Webhooks::WhatsappEventsJob.perform_now(message_payload.deep_dup) }.to raise_error('boom')

      allow(ContactInboxSourceIdResolver).to receive(:new).and_call_original
      expect { Webhooks::WhatsappEventsJob.perform_now(message_payload.deep_dup) }
        .to change { inbox.messages.incoming.count }.by(1)
    end

    # Required test 13: releasing the lock must not reopen the door to duplicates.
    it 'still suppresses a duplicate delivery of a message it already persisted' do
      Webhooks::WhatsappEventsJob.perform_now(message_payload.deep_dup)

      expect { Webhooks::WhatsappEventsJob.perform_now(message_payload.deep_dup) }
        .not_to(change { inbox.messages.incoming.count })
    end
  end

  describe 'webhook signature verification' do
    let(:app_secret) { 'an-app-secret' }

    def signature_for(body, secret)
      "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    end

    before { channel }

    # Required test 10: verification stays enforced. This is never "fixed" by switching it off.
    it 'rejects a payload whose signature does not match' do
      with_modified_env WHATSAPP_APP_SECRET: app_secret do
        post "/webhooks/whatsapp/#{channel.phone_number}",
             params: message_payload.to_json,
             headers: { 'Content-Type' => 'application/json', 'X-Hub-Signature-256' => signature_for('{}', app_secret) }
      end
      expect(response).to have_http_status(:unauthorized)
    end

    it 'accepts a correctly signed payload' do
      body = message_payload.to_json
      with_modified_env WHATSAPP_APP_SECRET: app_secret do
        post "/webhooks/whatsapp/#{channel.phone_number}",
             params: body,
             headers: { 'Content-Type' => 'application/json', 'X-Hub-Signature-256' => signature_for(body, app_secret) }
      end
      expect(response).to have_http_status(:ok)
    end

    # Required test 9: with no secret configured anywhere there is nothing to verify against, and the controller
    # refuses. That is correct, and it is why the diagnosis reports a blank secret as a configuration failure
    # rather than this being a code bug to work around.
    it 'refuses every payload when no app secret is configured' do
      body = message_payload.to_json
      post "/webhooks/whatsapp/#{channel.phone_number}",
           params: body,
           headers: { 'Content-Type' => 'application/json', 'X-Hub-Signature-256' => signature_for(body, app_secret) }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'the 24-hour window is distinguished from a Meta rejection' do
    let(:conversation) { create(:conversation, inbox: inbox, account: account) }

    # Required test 17: Meta is never contacted, so the reason must not read like a delivery failure.
    it 'fails a plain reply locally, without calling Meta, and says why' do
      stub = stub_request(:post, /graph\.facebook\.com/)
      message = create(:message, conversation: conversation, inbox: inbox, account: account,
                                 message_type: :outgoing, content: 'are you there?')

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      message.reload
      expect(message.status).to eq('failed')
      expect(message.external_error).to eq(I18n.t('errors.whatsapp.message_outside_messaging_window'))
      expect(stub).not_to have_been_requested
    end

    # Required test 18: a template takes the first branch of perform_reply and never consults the window.
    it 'lets an approved template through the closed window' do
      stub_request(:post, /graph\.facebook\.com/)
        .to_return(status: 200, body: { messages: [{ id: 'wamid.SENT' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      allow(Whatsapp::TemplateProcessorService).to receive(:new).and_return(
        instance_double(Whatsapp::TemplateProcessorService, call: ['greeting', nil, 'en_US', []])
      )
      message = create(:message, conversation: conversation, inbox: inbox, account: account,
                                 message_type: :outgoing, content: 'hello',
                                 additional_attributes: { 'template_params' => { 'name' => 'greeting' } })

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload.external_error).to be_nil
      expect(message.reload.status).not_to eq('failed')
    end
  end

  describe 'a manual retry keeps the provider reason' do
    let(:agent) { create(:user, account: account, role: :administrator) }
    let(:conversation) { create(:conversation, inbox: inbox, account: account) }
    let(:failed_message) do
      create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :outgoing,
                       status: :failed, external_error: '131047: more than 24 hours have passed')
    end

    before { create(:inbox_member, user: agent, inbox: inbox) }

    # Required test 14.
    it 'preserves the original Meta error after the retry clears it' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{failed_message.id}/retry",
           headers: agent.create_new_auth_token

      failed_message.reload
      expect(failed_message.content_attributes['previous_external_error'])
        .to eq('131047: more than 24 hours have passed')
      expect(failed_message.content_attributes['retried_at']).to be_present
    end
  end

  describe 'media authorization errors' do
    # Required test 6: only Meta's own OAuth verdict may latch the channel.
    it 'does not count a 401 Meta attributes to something other than OAuth' do
      service = Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: message_payload)
      response = instance_double(
        HTTParty::Response, unauthorized?: true,
                            parsed_response: { 'error' => { 'type' => 'GraphMethodException', 'code' => 100 } }
      )

      expect { service.send(:count_authorization_error, response) }
        .not_to change(channel, :authorization_error_count)
    end

    it 'counts a 401 Meta attributes to OAuth' do
      service = Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: message_payload)
      response = instance_double(
        HTTParty::Response, unauthorized?: true,
                            parsed_response: { 'error' => { 'type' => 'OAuthException', 'code' => 190 } }
      )

      expect { service.send(:count_authorization_error, response) }
        .to change { channel.reload.authorization_error_count }.by(1)
    end

    it 'counts a 401 whose body cannot be read, keeping the safer behaviour' do
      service = Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: message_payload)
      response = instance_double(HTTParty::Response, unauthorized?: true, parsed_response: 'not json')

      expect { service.send(:count_authorization_error, response) }
        .to change { channel.reload.authorization_error_count }.by(1)
    end
  end

  describe 'the reauthorization latch lifecycle' do
    # Required test 7: the supported path clears both the flag and the counter.
    it 'is cleared by the supported reauthorization path' do
      channel.authorization_error!
      channel.prompt_reauthorization!
      expect(channel.reauthorization_required?).to be true
      expect(channel.authorization_error_count).to be >= 1

      channel.reauthorized!

      expect(channel.reauthorization_required?).to be false
      expect(channel.authorization_error_count).to eq(0)
    end

    # Required test 8: a stale latch no longer suppresses inbound, which is what made it dangerous.
    it 'does not suppress inbound while it is still set' do
      channel.prompt_reauthorization!

      expect { Webhooks::WhatsappEventsJob.perform_now(message_payload.deep_dup) }
        .to change { inbox.messages.incoming.count }.by(1)
    end
  end

  describe 'no second ingestion engine' do
    # Required test 20: the fix stayed inside the existing pipeline.
    it 'routes inbound through the one existing job and service' do
      expect(Webhooks::WhatsappEventsJob).to be < ApplicationJob
      expect(Whatsapp::IncomingMessageWhatsappCloudService).to be < Whatsapp::IncomingMessageBaseService
      expect(
        Dir[Rails.root.join('app/controllers/webhooks/whatsapp*.rb')] +
        Dir[Rails.root.join('{enterprise,custom}/app/controllers/**/webhooks/whatsapp*.rb')]
      ).to contain_exactly(Rails.root.join('app/controllers/webhooks/whatsapp_controller.rb').to_s)
    end
  end

  describe 'a webhook setup failure does not look like a success' do
    let(:setup_service) { instance_double(Whatsapp::WebhookSetupService) }

    before do
      allow(Whatsapp::WebhookSetupService).to receive(:new).and_return(setup_service)
      allow(setup_service).to receive(:perform).and_raise(StandardError, 'callback registration refused')
    end

    # Required test 1. `setup_webhooks` used to rescue the failure itself and return nil, so an explicit caller was
    # told setup had succeeded when it had not.
    it 'raises from the bang version the explicit callers use' do
      expect { channel.setup_webhooks!(is_coexistence: false) }
        .to raise_error(StandardError, 'callback registration refused')
    end

    it 'returns false from the after_commit version instead of nil' do
      expect(channel.setup_webhooks(is_coexistence: false)).to be false
    end

    it 'propagates out of the embedded signup service' do
      allow(Whatsapp::ChannelCreationService).to receive(:new).and_return(
        instance_double(Whatsapp::ChannelCreationService, perform: channel)
      )
      allow(Whatsapp::TokenExchangeService).to receive(:new).and_return(
        instance_double(Whatsapp::TokenExchangeService, perform: 'a-token')
      )
      allow(Whatsapp::PhoneInfoService).to receive(:new).and_return(
        instance_double(Whatsapp::PhoneInfoService,
                        perform: { phone_number_id: '1', phone_number: '+1', business_name: 'B' })
      )

      expect do
        Whatsapp::EmbeddedSignupService.new(
          account: account, params: { code: 'c', business_id: 'b', waba_id: 'WABA' }
        ).perform
      end.to raise_error(StandardError, 'callback registration refused')
    end

    # Required test 2: the state left behind has to say what happened. One log line is not enough for a failure
    # that disables inbound until somebody reauthorizes, so it also reaches the existing error reporting.
    it 'latches the channel, reports to the exception tracker and logs a structured line' do
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      allow(Rails.logger).to receive(:error)

      expect(Rails.logger).to receive(:error).with(
        a_string_including('[WHATSAPP INGEST] event=webhook_setup_failed', "channel_id=#{channel.id}",
                           'failure_class=StandardError')
      )
      expect { channel.setup_webhooks!(is_coexistence: false) }.to raise_error(StandardError)

      expect(tracker).to have_received(:capture_exception)
      expect(channel.reauthorization_required?).to be true
    end
  end

  describe 'a failed media download does not cost the message' do
    let(:media_payload) do
      payload = message_payload.deep_dup
      payload[:entry][0][:changes][0][:value][:messages] = [
        { from: '15559998888', id: 'wamid.MEDIA1', timestamp: '1700000000', type: 'image',
          image: { id: 'media-1', mime_type: 'image/jpeg', caption: 'the receipt' } }
      ]
      payload
    end

    before do
      stub_request(:get, %r{graph\.facebook\.com/.*/media-1})
        .to_return(status: 401,
                   body: { error: { message: 'Unsupported get request.', type: 'GraphMethodException', code: 100 } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    # Required test 5. The architecture already supported an attachment-less message — attach_files returns early
    # and @message.save! still runs — which is why discarding the whole event protected nothing.
    it 'persists the message and its caption with no attachment' do
      expect { Webhooks::WhatsappEventsJob.perform_now(media_payload) }
        .to change { inbox.messages.incoming.count }.by(1)

      message = inbox.messages.incoming.last
      expect(message.source_id).to eq('wamid.MEDIA1')
      expect(message.content).to eq('the receipt')
      expect(message.attachments).to be_empty
    end

    it 'does not latch the channel on a single non-OAuth media failure' do
      Webhooks::WhatsappEventsJob.perform_now(media_payload)

      expect(channel.reload.reauthorization_required?).to be false
      expect(channel.authorization_error_count).to eq(0)
    end
  end

  describe 'authorization error threshold semantics' do
    # Required test 6: one error is not a disconnect; the threshold is what latches.
    it 'latches only once the threshold is reached' do
      channel.authorization_error!
      expect(channel.authorization_error_count).to eq(1)
      expect(channel.reauthorization_required?).to be false

      channel.authorization_error!

      expect(channel.authorization_error_count).to eq(Channel::Whatsapp::AUTHORIZATION_ERROR_THRESHOLD)
      expect(channel.reauthorization_required?).to be true
    end
  end

  describe 'credentials never travel in a URL' do
    # Required test 15. Two call sites ran on every channel validation, so a live token was being written to logs
    # routinely. Meta accepts the bearer header for every read; the two endpoints whose contract requires a
    # parameter are documented in app/services/whatsapp/facebook_api_client.rb.
    it 'sends the token as a bearer header on a template read, not as a query value' do
      requested = []
      WebMock.after_request { |request, _response| requested << request.uri.to_s }
      stub_request(:get, /graph\.facebook\.com/)
        .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel).validate_provider_config?

      expect(requested).not_to be_empty
      expect(requested.join(' ')).not_to include('access_token')
      expect(WebMock).to have_requested(:get, /graph\.facebook\.com/)
        .with(headers: { 'Authorization' => "Bearer #{channel.provider_config['api_key']}" })
    ensure
      WebMock.reset_callbacks
    end

    it 'keeps credential query parameters out of the WhatsApp request construction' do
      sources = Dir[Rails.root.join('app/services/whatsapp/**/*.rb')] +
                Dir[Rails.root.join('{enterprise,custom}/app/services/whatsapp/**/*.rb')] +
                [Rails.root.join('app/models/channel/whatsapp.rb').to_s]
      # Two shapes, both precise: an interpolated query string, and an HTTParty `query:` hash holding a
      # credential. A Ruby keyword argument named access_token is neither, which is why this is not a bare grep.
      in_url = /[?&](access_token|api_key)=/
      in_query_hash = /query:\s*\{[^}]*\b(access_token|api_key)\b/m

      offenders = sources.reject { |path| path.end_with?('facebook_api_client.rb') }.select do |path|
        body = File.read(path)
        body.match?(in_query_hash) ||
          File.readlines(path).any? { |line| line.match?(in_url) && !line.strip.start_with?('#') }
      end

      expect(offenders).to be_empty
    end

    # The two documented exceptions, kept honest: Meta's contract requires a parameter for each, and nothing else
    # in that class may do the same.
    it 'limits credential parameters to the two endpoints Meta requires them on' do
      body = File.read(Rails.root.join('app/services/whatsapp/facebook_api_client.rb'))
      credential_blocks = body.scan(/query:\s*\{[^}]*\b(?:access_token|client_secret|input_token)\b[^}]*\}/m)

      expect(credential_blocks.size).to eq(2)
      expect(body).to include('oauth/access_token')
      expect(body).to include('debug_token')
    end
  end

  describe 'callback source and override selection' do
    let(:expected) { 'https://app.lynomia.com/webhooks/whatsapp/+96590000001' }
    let(:classification) { Whatsapp::Diagnosis::CallbackClassification }

    # Required test 16. A phone-level override takes precedence over the Meta App's configuration and is invisible
    # in the dashboard, so the diagnosis has to report a source as well as a verdict.
    it 'reports a matching phone-level override as a match attributed to the override' do
      result = classification.new(expected: expected,
                                  configuration: { 'override_callback_uri' => expected,
                                                   'application' => 'https://elsewhere.test/hook' })

      expect(result.verdict).to eq(classification::MATCH)
      expect(result.source).to eq(classification::PHONE_LEVEL_OVERRIDE)
      expect(result.to_s).to eq('MATCH (PHONE_LEVEL_OVERRIDE)')
    end

    it 'lets the override win over a matching app-level callback, because Meta does' do
      result = classification.new(expected: expected,
                                  configuration: { 'override_callback_uri' => 'https://stale.test/hook',
                                                   'application' => expected })

      expect(result.verdict).to eq(classification::MISMATCH)
      expect(result.source).to eq(classification::PHONE_LEVEL_OVERRIDE)
      expect(result.note).to include('Re-register through Whatsapp::WebhookSetupService#register_callback')
    end

    it 'attributes a match with no override to the app-level callback' do
      result = classification.new(expected: expected, configuration: { 'application' => expected })

      expect(result.to_s).to eq('MATCH (APP_LEVEL_CALLBACK)')
    end

    it 'reports UNKNOWN rather than a pass when Meta returned nothing' do
      result = classification.new(expected: expected, configuration: nil)

      expect(result.verdict).to eq(classification::UNKNOWN)
      expect(result.source).to eq(classification::UNKNOWN)
      expect(result.note).to include('UNPROVEN')
    end

    it 'never prints an override query string, which can carry a verify token' do
      printed = classification.safe('https://app.lynomia.test/webhooks/whatsapp/+1?verify_token=s3cret')

      expect(printed).not_to include('s3cret')
      expect(printed).to include('app.lynomia.test')
    end

    # Required test 16, the other half: for a Cloud delivery the payload metadata is the only acceptable source.
    # Falling back to the URL segment would file one number's customer message under another channel's inbox.
    it 'refuses a Cloud payload whose metadata matches no channel, rather than trusting the URL' do
      other = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        validate_provider_config: false, sync_templates: false)
      payload = message_payload.deep_dup
      payload[:entry][0][:changes][0][:value][:metadata][:phone_number_id] = 'not-a-known-id'
      payload[:phone_number] = other.phone_number

      expect { Webhooks::WhatsappEventsJob.perform_now(payload) }.not_to(change(Message, :count))
    end
  end
end
