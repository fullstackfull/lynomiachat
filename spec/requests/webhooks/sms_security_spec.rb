require 'rails_helper'

# SC1 and SC2 of the P10 security closure (docs/p11/00-p10-security-closure.md).
#
# Before this, POST /webhooks/sms/:phone_number was unauthenticated and chose the receiving channel from the
# request body's `to` field, so anyone who knew a configured Bandwidth number could post forged inbound
# messages into the account that owns it. These examples are written from the attacker's side: each one is a
# request a stranger can make, and asserts what the product does with it.
RSpec.describe 'Bandwidth SMS webhook security', type: :request do
  let!(:victim_channel) { create(:channel_sms, phone_number: '+15550000001') }
  let!(:attacker_channel) { create(:channel_sms, phone_number: '+15550000002') }

  let(:callback_url) { "/webhooks/sms/#{victim_channel.phone_number.delete_prefix('+')}" }

  def inbound_event(to:, text: 'hello', id: 'bw-message-1', from: '+14155550000')
    {
      type: 'message-received',
      time: '2026-02-02T23:14:05.309Z',
      description: 'Incoming message received',
      to: to,
      message: {
        id: id, owner: to, applicationId: 'app-1', time: '2026-02-02T23:14:05.262Z',
        segmentCount: 1, direction: 'in', to: [to], from: from, text: text
      }
    }
  end

  def credentials(username, password)
    ActionController::HttpAuthentication::Basic.encode_credentials(username, password)
  end

  describe 'authentication' do
    it 'rejects a delivery that carries no credentials, and issues the challenge Bandwidth needs to retry' do
      expect { post callback_url, params: [inbound_event(to: victim_channel.phone_number)], as: :json }
        .not_to(change { victim_channel.inbox.messages.count })

      expect(response).to have_http_status(:unauthorized)
      # Bandwidth sends the first delivery unauthenticated and only retries if the 401 carries this header.
      # Without it the callback never arrives at all, so its absence would be a silent outage.
      expect(response.headers['WWW-Authenticate']).to match(/\ABasic realm=/)
    end

    it 'rejects a wrong password' do
      post callback_url,
           params: [inbound_event(to: victim_channel.phone_number)],
           headers: { 'HTTP_AUTHORIZATION' => credentials('bw-user', 'wrong') },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(victim_channel.inbox.messages.count).to eq(0)
    end

    it 'accepts the credentials configured on the channel' do
      post callback_url,
           params: [inbound_event(to: victim_channel.phone_number)],
           headers: { 'HTTP_AUTHORIZATION' => credentials('bw-user', 'bw-secret') },
           as: :json

      expect(response).to have_http_status(:ok)
      perform_enqueued_jobs
      expect(victim_channel.inbox.messages.pluck(:content)).to eq(['hello'])
    end

    it 'fails closed for a channel configured before callback credentials existed' do
      legacy = create(:channel_sms, :without_callback_credentials, phone_number: '+15550000009')

      post "/webhooks/sms/#{legacy.phone_number.delete_prefix('+')}",
           params: [inbound_event(to: legacy.phone_number)],
           headers: { 'HTTP_AUTHORIZATION' => credentials('bw-user', 'bw-secret') },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(legacy.inbox.messages.count).to eq(0)
    end

    it 'answers an unknown number exactly as it answers a bad password, so it reveals no configured numbers' do
      post '/webhooks/sms/15559999999', params: [inbound_event(to: '+15559999999')], as: :json
      unknown = [response.status, response.headers['WWW-Authenticate']]

      post callback_url, params: [inbound_event(to: victim_channel.phone_number)], as: :json

      expect(unknown).to eq([response.status, response.headers['WWW-Authenticate']])
    end
  end

  describe 'tenant selection' do
    it 'ignores the body and uses the number in the callback URL, so one tenant cannot post into another' do
      # The attacker holds valid credentials for their OWN channel and aims the body at the victim's number.
      post "/webhooks/sms/#{attacker_channel.phone_number.delete_prefix('+')}",
           params: [inbound_event(to: victim_channel.phone_number, text: 'forged')],
           headers: { 'HTTP_AUTHORIZATION' => credentials('bw-user', 'bw-secret') },
           as: :json

      expect(response).to have_http_status(:ok)
      perform_enqueued_jobs

      expect(victim_channel.inbox.messages.count).to eq(0)
      expect(attacker_channel.inbox.messages.pluck(:content)).to eq(['forged'])
    end

    it 'does not let a job forged without a channel_id choose a tenant from its payload' do
      # Belt for a rolling deploy: a job enqueued by the old controller carries no channel_id. It must be
      # dropped rather than fall back to resolving the tenant from `to`.
      expect { Webhooks::SmsEventsJob.perform_now(inbound_event(to: victim_channel.phone_number)) }
        .not_to(change(Message, :count))
    end
  end

  describe 'batched deliveries' do
    it 'processes every event in the array, not only the first' do
      events = [
        inbound_event(to: victim_channel.phone_number, text: 'first', id: 'bw-1'),
        inbound_event(to: victim_channel.phone_number, text: 'second', id: 'bw-2'),
        inbound_event(to: victim_channel.phone_number, text: 'third', id: 'bw-3')
      ]

      post callback_url, params: events,
                         headers: { 'HTTP_AUTHORIZATION' => credentials('bw-user', 'bw-secret') }, as: :json
      perform_enqueued_jobs

      expect(victim_channel.inbox.messages.pluck(:content)).to contain_exactly('first', 'second', 'third')
    end
  end

  describe 'redelivery' do
    it 'does not record the same message twice when Bandwidth retries a callback' do
      2.times do
        post callback_url,
             params: [inbound_event(to: victim_channel.phone_number, id: 'bw-same')],
             headers: { 'HTTP_AUTHORIZATION' => credentials('bw-user', 'bw-secret') }, as: :json
        perform_enqueued_jobs
      end

      expect(victim_channel.inbox.messages.count).to eq(1)
    end
  end

  describe 'delivery receipts (SC2)' do
    let(:conversation) do
      contact = create(:contact, account: victim_channel.account, phone_number: '+14155550000')
      contact_inbox = create(:contact_inbox, source_id: '+14155550000', contact: contact, inbox: victim_channel.inbox)
      create(:conversation, contact: contact, inbox: victim_channel.inbox, contact_inbox: contact_inbox)
    end

    def receipt(type:, error_code: nil)
      event = {
        type: type, time: '2026-02-02T23:14:05.309Z', description: 'Message delivered to handset.',
        to: victim_channel.phone_number, message: { id: 'bw-outbound-1' }
      }
      event[:errorCode] = error_code if error_code
      event
    end

    before do
      create(:message, account: victim_channel.account, inbox: victim_channel.inbox,
                       conversation: conversation, status: :sent, source_id: 'bw-outbound-1')
    end

    # Not mocked on purpose. The old job spec stubbed Sms::DeliveryStatusService, which is why nobody noticed
    # the job was calling it with a `channel:` keyword it does not accept and with the nested `message` where
    # it reads the envelope. Every receipt raised ArgumentError and no status was ever stored.
    it 'records a delivered receipt end to end' do
      post callback_url, params: [receipt(type: 'message-delivered')],
                         headers: { 'HTTP_AUTHORIZATION' => credentials('bw-user', 'bw-secret') }, as: :json
      perform_enqueued_jobs

      expect(conversation.messages.last.reload.status).to eq('delivered')
    end

    it 'records a failed receipt with the provider error from the envelope' do
      post callback_url, params: [receipt(type: 'message-failed', error_code: 4432)],
                         headers: { 'HTTP_AUTHORIZATION' => credentials('bw-user', 'bw-secret') }, as: :json
      perform_enqueued_jobs

      message = conversation.messages.last.reload
      expect(message.status).to eq('failed')
      expect(message.external_error).to eq('4432 - Message delivered to handset.')
    end
  end

  describe 'secret safety' do
    it 'never echoes the callback credentials in the response body' do
      post callback_url,
           params: [inbound_event(to: victim_channel.phone_number)],
           headers: { 'HTTP_AUTHORIZATION' => credentials('bw-user', 'bw-secret') }, as: :json

      expect(response.body).not_to include('bw-secret')
      expect(response.body).not_to include('api_secret')
    end
  end
end
