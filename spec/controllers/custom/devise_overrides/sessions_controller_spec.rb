require 'rails_helper'

# The sign-in / sign-out audit writer. Chatwoot Enterprise wrote these rows by hand from
# Enterprise::DeviseOverrides::SessionsController; that controller went with the overlay and took the
# "Access" family of Lynomia's documented audit log with it. These examples pin the behaviour the
# relocated Custom:: module has to reproduce, field for field.
#
# The field-fidelity example asserts every column of one row, which is the point of it; same file-level
# exemption the Commerce controller specs use for the same reason.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe DeviseOverrides::SessionsController, type: :controller do
  include Devise::Test::ControllerHelpers

  let(:password) { 'Test@123456' }
  let!(:account) { create(:account) }
  let!(:user) { create(:user, password: password, account: account) }

  before { request.env['devise.mapping'] = Devise.mappings[:user] }

  def session_audits(action)
    Custom::AuditLog.where(auditable_type: 'User', auditable_id: user.id, action: action)
  end

  describe 'the writer is Lynomia-owned' do
    it 'is prepended from custom/ and names no Enterprise module' do
      owner = described_class.ancestors.find do |m|
        (m.instance_methods(false) + m.private_instance_methods(false)).include?(:create_audit_event)
      end
      expect(owner).to eq(Custom::DeviseOverrides::SessionsController)
      expect(described_class.ancestors.map { |m| m.name.to_s }).to all(satisfy { |n| !n.start_with?('Enterprise') })
      expect(Audited.audit_class.name).to eq('Custom::AuditLog')
    end
  end

  describe 'successful sign-in' do
    it 'writes exactly one sign_in row, with the fields the Enterprise writer wrote' do
      expect { post :create, params: { email: user.email, password: password } }
        .to change { session_audits('sign_in').count }.from(0).to(1)
      expect(response).to have_http_status(:success)

      row = session_audits('sign_in').first
      expect(row.auditable_type).to eq('User')
      expect(row.auditable_id).to eq(user.id)
      expect(row.user_id).to eq(user.id)
      expect(row.user_type).to eq('User')
      expect(row.username).to eq(user.email)
      expect(row.action).to eq('sign_in')
      expect(row.associated_type).to eq('Account')
      expect(row.associated_id).to eq(account.id)
      expect(row.version).to eq(1)
      expect(row.request_uuid).to be_present
      expect(row.created_at).to be_present
      # audited_changes is never set for a session event
      expect(row.audited_changes).to be_blank
    end

    it 'records the remote address the Audited sweeper captured' do
      post :create, params: { email: user.email, password: password }
      expect(session_audits('sign_in').first.remote_address).to eq(request.remote_ip)
    end

    it 'leaves geolocation unresolved — Lynomia runs no ip_lookup job' do
      post :create, params: { email: user.email, password: password }
      row = session_audits('sign_in').first
      expect([row.city, row.country, row.country_code]).to all(be_nil)
    end
  end

  describe 'successful sign-out' do
    it 'writes exactly one sign_out row' do
      auth = user.create_new_auth_token
      auth.each { |k, v| request.headers[k] = v }

      expect { delete :destroy }.to change { session_audits('sign_out').count }.from(0).to(1)

      row = session_audits('sign_out').first
      expect(row.action).to eq('sign_out')
      expect(row.auditable_id).to eq(user.id)
      expect(row.associated_id).to eq(account.id)
      expect(row.username).to eq(user.email)
    end
  end

  describe 'the guards the Enterprise writer had' do
    it 'writes nothing when authentication fails' do
      expect { post :create, params: { email: user.email, password: 'wrong' } }
        .not_to change(Custom::AuditLog, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'writes nothing on sign-out without a valid token, and does not raise' do
      expect { delete :destroy }.not_to change(Custom::AuditLog, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'writes nothing for a user who belongs to no account' do
      orphan = create(:user, password: password)
      orphan.account_users.destroy_all

      expect { post :create, params: { email: orphan.email, password: password } }
        .not_to change(Custom::AuditLog, :count)
    end
  end

  describe 'one row per account, versioned in order' do
    let!(:second_account) { create(:account) }

    before { create(:account_user, user: user, account: second_account) }

    it 'writes a row for each account, sharing one request_uuid and timestamp' do
      expect { post :create, params: { email: user.email, password: password } }
        .to change { session_audits('sign_in').count }.from(0).to(2)

      rows = session_audits('sign_in').order(:version)
      expect(rows.map(&:associated_id)).to contain_exactly(account.id, second_account.id)
      expect(rows.map(&:version)).to eq([1, 2])
      expect(rows.map(&:request_uuid).uniq.size).to eq(1)
      expect(rows.map(&:created_at).uniq.size).to eq(1)
    end
  end

  describe 'repeated sign-ins' do
    it 'continues the version sequence rather than colliding' do
      post :create, params: { email: user.email, password: password }
      post :create, params: { email: user.email, password: password }

      expect(session_audits('sign_in').count).to eq(2)
      expect(session_audits('sign_in').order(:version).map(&:version)).to eq([1, 2])
    end
  end

  describe 'no duplicate writer' do
    it 'one sign-in produces one row and no other audit row for the user' do
      post :create, params: { email: user.email, password: password }
      expect(Custom::AuditLog.where(auditable_type: 'User', auditable_id: user.id).count).to eq(1)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
