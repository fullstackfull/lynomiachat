require 'rails_helper'

RSpec.describe 'Super Admin', type: :request do
  describe '/super_admin' do
    it 'renders the login page' do
      with_modified_env LOGRAGE_ENABLED: 'true' do
        get '/super_admin/sign_in'
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'POST /super_admin/sign_in' do
    let(:super_admin) { create(:super_admin, password: 'Password1!') }

    it 'redirects to the dashboard on successful login' do
      post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: 'Password1!' } }
      expect(response).to redirect_to(super_admin_root_path)
    end

    it 'redirects back to the login page on invalid credentials' do
      post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: 'wrong' } }
      expect(response).to redirect_to(super_admin_session_path)
    end
  end

  # A super admin reaches every account's data, so the password alone must stop being enough once they turn on
  # two-factor authentication.
  describe 'POST /super_admin/sign_in with two-factor authentication enabled' do
    let(:super_admin) { create(:super_admin, password: 'Password1!') }

    def sign_in_with(code)
      post '/super_admin/sign_in', params: { super_admin: { email: super_admin.email, password: 'Password1!', otp_code: code } }
    end

    # otp_required_for_login is a plain boolean, so this runs wherever the suite runs -- it is the regression test for
    # the defect itself, which was that the password alone signed the super admin in.
    context 'when only the flag can be set' do
      before { super_admin.update!(otp_required_for_login: true) }

      it 'refuses a correct password with no authentication code' do
        sign_in_with(nil)

        expect(response).to redirect_to(super_admin_session_path)
        expect(flash[:error]).to eq(SuperAdmin::Devise::SessionsController::MFA_ERROR)
      end

      it 'refuses a correct password with a wrong authentication code' do
        sign_in_with('000000')
        expect(response).to redirect_to(super_admin_session_path)
      end
    end

    # Verifying a real code needs the encrypted otp_secret, so these follow the suite's existing guard.
    context 'when the installation can store an OTP secret' do
      before do
        skip('Skipping since MFA is not configured in this environment') unless Chatwoot.encryption_configured?
        super_admin.enable_two_factor!
        super_admin.update!(otp_required_for_login: true)
      end

      it 'signs in with a valid authenticator code' do
        sign_in_with(super_admin.current_otp)
        expect(response).to redirect_to(super_admin_root_path)
      end

      it 'signs in with a valid backup code' do
        codes = Mfa::ManagementService.new(user: super_admin).generate_backup_codes!

        sign_in_with(codes.first)

        expect(response).to redirect_to(super_admin_root_path)
      end

      it 'refuses a backup code that was already used' do
        codes = Mfa::ManagementService.new(user: super_admin).generate_backup_codes!
        sign_in_with(codes.first)
        get '/super_admin/logout'

        sign_in_with(codes.first)

        expect(response).to redirect_to(super_admin_session_path)
      end
    end
  end
end
