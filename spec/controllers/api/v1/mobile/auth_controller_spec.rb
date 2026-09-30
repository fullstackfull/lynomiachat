require 'rails_helper'

RSpec.describe 'Mobile Auth API', type: :request do
  describe 'POST /api/v1/mobile/auth/google' do
    let(:user) { create(:user) }
    let(:verifier) { instance_double(MobileAuth::TokenVerifier) }

    before do
      allow(MobileAuth::TokenVerifier).to receive(:new).with('google').and_return(verifier)
      allow(verifier).to receive(:verify).with('google-id-token')
                                         .and_return({ uid: 'google-uid-1', email: user.email, email_verified: true, name: user.name })
    end

    it 'signs the user in and tracks the session like the web sign-in' do
      post '/api/v1/mobile/auth/google',
           params: { id_token: 'google-id-token' },
           headers: { 'X-Chatwoot-Client-Name' => 'Lynomia Mobile', 'X-Chatwoot-Platform' => 'android',
                      'X-Chatwoot-Device-Model' => 'Pixel 8' },
           as: :json

      expect(response).to have_http_status(:success)
      client_id = response.parsed_body['auth']['client']
      session = user.reload.user_sessions.find_by(client_id: client_id)
      expect(session).to be_present
      expect(session.browser_name).to eq('Lynomia Mobile')
      expect(session.device_name).to eq('Android')
    end
  end
end
