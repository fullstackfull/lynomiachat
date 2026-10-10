require 'rails_helper'

# See the note in spec/controllers/twilio/callbacks_controller_spec.rb: this endpoint had the same defect on
# the outbound side, where a forged body marked an existing message failed with an attacker-chosen error
# string that agents read (docs/p11/00-p10-security-closure.md, SEC-2).
RSpec.describe 'Twilio::DeliveryStatusController', type: :request do
  include Rails.application.routes.url_helpers

  describe 'POST /twilio/delivery_status' do
    let(:auth_token) { 'twilio-auth-token' }
    let!(:channel) do
      # :with_phone_number clears messaging_service_sid; the model forbids both at once.
      create(:channel_twilio_sms, :with_phone_number, account_sid: 'AC123', auth_token: auth_token,
                                                      phone_number: '+0987654321', medium: :sms)
    end
    let(:params) do
      { 'MessageSid' => 'SM123', 'MessageStatus' => 'delivered', 'AccountSid' => 'AC123', 'From' => '+0987654321' }
    end

    def signed_post(body)
      signature = Twilio::Security::RequestValidator.new(auth_token)
                                                    .build_signature_for(twilio_delivery_status_index_url, body)
      post twilio_delivery_status_index_url, params: body, headers: { 'HTTP_X_TWILIO_SIGNATURE' => signature }
    end

    it 'enqueues the Twilio delivery status job' do
      expect { signed_post(params) }.to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob).with(params)
    end

    it 'returns no content status' do
      signed_post(params)
      expect(response).to have_http_status(:no_content)
    end
  end
end
