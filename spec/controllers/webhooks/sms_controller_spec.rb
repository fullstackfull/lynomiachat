require 'rails_helper'

RSpec.describe 'Webhooks::SmsController', type: :request do
  describe 'POST /webhooks/sms/{:phone_number}' do
    let!(:channel) { create(:channel_sms, phone_number: '+15551230001') }
    let(:url) { "/webhooks/sms/#{channel.phone_number.delete_prefix('+')}" }
    let(:auth) { ActionController::HttpAuthentication::Basic.encode_credentials('bw-user', 'bw-secret') }
    let(:event) { { type: 'message-received', to: channel.phone_number, message: { id: 'bw-1', from: '+14155550000', text: 'hello' } } }

    # This used to post an unauthenticated body and assert only that the job was enqueued, which is exactly
    # the behaviour SC1 removed (docs/p11/00-p10-security-closure.md). The adversarial cases live in
    # spec/requests/webhooks/sms_security_spec.rb.
    it 'enqueues the job with the server-resolved channel once the delivery is authenticated' do
      expect(Webhooks::SmsEventsJob).to receive(:perform_later).with(hash_including('channel_id' => channel.id))

      post url, params: [event], headers: { 'HTTP_AUTHORIZATION' => auth }, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'does not enqueue anything for an unauthenticated delivery' do
      expect(Webhooks::SmsEventsJob).not_to receive(:perform_later)

      post url, params: [event], as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
