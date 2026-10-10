require 'rails_helper'

# Lynomia (docs/p11/00-p10-security-closure.md, SEC-1). This endpoint used to accept any unauthenticated body
# and pick the receiving channel from body fields -- a Twilio number is a business's public phone number and
# an Account SID is not a secret, so anyone holding both could inject inbound messages into that account. It
# now requires Twilio's X-Twilio-Signature, verified against that channel's own auth token. The refusals are
# exercised in spec/requests/webhooks/twilio_signature_spec.rb.
RSpec.describe 'Twilio::CallbacksController', type: :request do
  include Rails.application.routes.url_helpers

  describe 'POST /twilio/callback' do
    let(:auth_token) { 'twilio-auth-token' }
    let!(:channel) do
      # :with_phone_number clears messaging_service_sid; the model forbids both at once.
      create(:channel_twilio_sms, :with_phone_number, account_sid: 'AC123', auth_token: auth_token,
                                                      phone_number: '+0987654321', medium: :sms)
    end

    let(:params) do
      {
        'From' => '+1234567890',
        'To' => '+0987654321',
        'Body' => 'Test message',
        'AccountSid' => 'AC123',
        'SmsSid' => 'SM123',
        'ExternalUserId' => 'IN.2081978709342942',
        'ParentExternalUserId' => 'IN.ENT.9081726354',
        'ProfileUsername' => 'muhsin',
        'ReferralCtwaClid' => 'AfjyUDlaIoiweZDnlzmDTEaG',
        'ReferralSourceId' => '120237244350960485',
        'ReferralSourceUrl' => 'https://fb.me/4tBfhWhjr',
        'ReferralSourceType' => 'ad',
        'ReferralHeadline' => 'German citizenship lawyer',
        'ReferralBody' => 'Fast-track your German citizenship',
        'ReferralMediaId' => '',
        'ReferralNumMedia' => '0'
      }
    end

    def signed_post(body)
      signature = Twilio::Security::RequestValidator.new(auth_token)
                                                    .build_signature_for(twilio_callback_index_url, body)
      post twilio_callback_index_url, params: body, headers: { 'HTTP_X_TWILIO_SIGNATURE' => signature }
    end

    it 'enqueues the Twilio events job' do
      expect { signed_post(params) }.to have_enqueued_job(Webhooks::TwilioEventsJob).with(params)
    end

    it 'returns no content status' do
      signed_post(params)
      expect(response).to have_http_status(:no_content)
    end

    it 'forwards the quoted message SID to the Twilio events job' do
      params['OriginalRepliedMessageSid'] = 'SMoriginal'

      expect { signed_post(params) }.to have_enqueued_job(Webhooks::TwilioEventsJob).with(params)
    end
  end
end
