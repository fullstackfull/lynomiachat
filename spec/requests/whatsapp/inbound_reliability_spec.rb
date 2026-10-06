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
end
