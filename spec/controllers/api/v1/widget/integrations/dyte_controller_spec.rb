require 'rails_helper'

RSpec.describe '/api/v1/widget/integrations/dyte', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, email: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:conversation) { create(:conversation, contact: contact, account: account, inbox: web_widget.inbox, contact_inbox: contact_inbox) }
  let(:payload) { { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id } }
  let(:token) { Widget::TokenService.new(payload: payload).generate_token }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: conversation.inbox) }

  # A second, unrelated visitor on the same website -- same inbox, own contact, own conversation, and a
  # widget token minted exactly the way the real widget mints one. Nothing about this visitor is forged.
  let(:other_contact) { create(:contact, account: account, email: nil) }
  let(:other_contact_inbox) { create(:contact_inbox, contact: other_contact, inbox: web_widget.inbox) }
  let(:other_conversation) do
    create(:conversation, contact: other_contact, account: account, inbox: web_widget.inbox, contact_inbox: other_contact_inbox)
  end
  let(:other_token) do
    Widget::TokenService.new(payload: { source_id: other_contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end
  let!(:integration_message) do
    create(:message, content_type: 'integrations',
                     content_attributes: { type: 'dyte', data: { meeting_id: 'm_id' } },
                     conversation: conversation, account: account, inbox: conversation.inbox)
  end

  before do
    allow(Integrations::Cloudflare::RealtimeKitCredentialsValidator).to receive(:validate)
      .and_return(Integrations::Cloudflare::RealtimeKitCredentialsValidator::Result.new(true, nil))
    create(:integrations_hook, :dyte, account: account)
  end

  describe 'POST /api/v1/widget/integrations/dyte/add_participant_to_meeting' do
    context 'when token is invalid' do
      it 'returns error' do
        post add_participant_to_meeting_api_v1_widget_integrations_dyte_url,
             params: { website_token: web_widget.website_token },
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when token is valid' do
      context 'when message is not an integration message' do
        it 'returns error' do
          post add_participant_to_meeting_api_v1_widget_integrations_dyte_url,
               headers: { 'X-Auth-Token' => token },
               params: { website_token: web_widget.website_token, message_id: message.id },
               as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          response_body = response.parsed_body
          expect(response_body['error']).to eq('Invalid message type. Action not permitted')
        end
      end

      context 'when message is an integration message' do
        before do
          stub_request(:post, 'https://api.cloudflare.com/client/v4/accounts/account_id/realtime/kit/app_id/meetings/m_id/participants')
            .to_return(
              status: 200,
              body: { success: true, data: { id: 'random_uuid', token: 'json-web-token' } }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it 'returns token' do
          post add_participant_to_meeting_api_v1_widget_integrations_dyte_url,
               headers: { 'X-Auth-Token' => token },
               params: { website_token: web_widget.website_token, message_id: integration_message.id },
               as: :json

          expect(response).to have_http_status(:success)
          response_body = response.parsed_body
          expect(response_body).to eq(
            {
              'id' => 'random_uuid', 'token' => 'json-web-token'
            }
          )
        end
      end

      context 'when the message belongs to another visitor in the same inbox' do
        # The vulnerability this guards: `set_message` used to search `@web_widget.inbox.messages`, so a
        # token that authorises conversation A also reached conversation B's messages. The response was a
        # RealtimeKit participant token for B's meeting, minted under B's identity, obtainable by anyone
        # who could read the public `website_token` from the host page and call /widget/config once.
        let!(:other_integration_message) do
          create(:message, content_type: 'integrations',
                           content_attributes: { type: 'dyte', data: { meeting_id: 'other_m_id' } },
                           conversation: other_conversation, account: account, inbox: web_widget.inbox)
        end

        it 'does not hand one visitor a participant token for another visitor meeting' do
          # Stubbed to SUCCEED, deliberately. If the lookup is scoped wrongly the request reaches this and
          # the attacker receives a usable meeting token, so the assertions below fail loudly on the real
          # leak rather than on some incidental downstream error.
          stub = stub_request(:post, 'https://api.cloudflare.com/client/v4/accounts/account_id/realtime/kit/app_id/meetings/other_m_id/participants')
                 .to_return(
                   status: 200,
                   body: { success: true, data: { id: 'leaked_uuid', token: 'leaked-json-web-token' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' }
                 )

          post add_participant_to_meeting_api_v1_widget_integrations_dyte_url,
               headers: { 'X-Auth-Token' => token },
               params: { website_token: web_widget.website_token, message_id: other_integration_message.id },
               as: :json

          expect(response).to have_http_status(:not_found)
          expect(response.body).not_to include('leaked-json-web-token')
          expect(stub).not_to have_been_requested
        end

        it 'still lets the second visitor join their own meeting' do
          stub_request(:post, 'https://api.cloudflare.com/client/v4/accounts/account_id/realtime/kit/app_id/meetings/other_m_id/participants')
            .to_return(
              status: 200,
              body: { success: true, data: { id: 'other_uuid', token: 'other-json-web-token' } }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          post add_participant_to_meeting_api_v1_widget_integrations_dyte_url,
               headers: { 'X-Auth-Token' => other_token },
               params: { website_token: web_widget.website_token, message_id: other_integration_message.id },
               as: :json

          expect(response).to have_http_status(:success)
          expect(response.parsed_body).to eq({ 'id' => 'other_uuid', 'token' => 'other-json-web-token' })
        end
      end
    end
  end
end
