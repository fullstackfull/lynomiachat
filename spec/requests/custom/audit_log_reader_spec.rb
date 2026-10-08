require 'rails_helper'

RSpec.describe 'Lynomia audit log reader', type: :request do
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  before { account.enable_features!('audit_logs') }

  it 'is the Lynomia controller on Custom::AuditLog, reachable at the documented path' do
    expect(Rails.application.routes.recognize_path("/api/v1/accounts/#{account.id}/audit_logs"))
      .to include(controller: 'api/v1/accounts/audit_logs', action: 'show')
    expect(Api::V1::Accounts::AuditLogsController.instance_method(:show).source_location.first)
      .to include('/custom/app/controllers/')
    expect(Audited.audit_class.name).to eq('Custom::AuditLog')
    expect('Enterprise::AuditLog'.safe_constantize).to be_nil
  end

  it 'returns the account audit rows to an administrator' do
    account.update!(name: 'Renamed Co')
    get "/api/v1/accounts/#{account.id}/audit_logs", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['audit_logs']).to be_an(Array)
    expect(body['audit_logs']).to be_present
    expect(body['per_page']).to eq(25)
    expect(body['audit_logs'].first.keys).to include('auditable_type', 'action', 'username', 'created_at', 'remote_address')
  end

  it 'denies a non-administrator' do
    get "/api/v1/accounts/#{account.id}/audit_logs", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns nothing when the account does not have the feature' do
    account.disable_features!('audit_logs')
    account.update!(name: 'Another name')
    get "/api/v1/accounts/#{account.id}/audit_logs", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['audit_logs']).to eq([])
  end

  it 'filters by auditable type, by user search and by date window' do
    account.update!(name: 'Filtered Co')
    get "/api/v1/accounts/#{account.id}/audit_logs", params: { types: ['Account'] },
                                                     headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['audit_logs'].map { |r| r['auditable_type'] }.uniq).to eq(['Account'])

    get "/api/v1/accounts/#{account.id}/audit_logs", params: { types: ['Inbox'] },
                                                     headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['audit_logs']).to eq([])

    get "/api/v1/accounts/#{account.id}/audit_logs", params: { q: 'no-such-person' },
                                                     headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['audit_logs']).to eq([])

    get "/api/v1/accounts/#{account.id}/audit_logs", params: { since: 1.day.from_now.to_i },
                                                     headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['audit_logs']).to eq([])

    get "/api/v1/accounts/#{account.id}/audit_logs", params: { since: 'not-a-number', until: 'nope' },
                                                     headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  # The Access family: rows the relocated session writer inserts with insert_all! must come back
  # through the relocated reader, under the same `types: ['User']` filter the UI's ACCESS group sends
  # (app/javascript/dashboard/helper/auditlogHelper.js EVENT_TYPE_GROUPS).
  it 'returns the sign-in and sign-out rows the session writer inserts' do
    Custom::AuditLog.insert_all!( # rubocop:disable Rails/SkipsModelValidations
      [
        { auditable_id: admin.id, auditable_type: 'User', user_id: admin.id, user_type: 'User',
          username: admin.email, action: 'sign_in', associated_id: account.id, associated_type: 'Account',
          version: 1, request_uuid: SecureRandom.uuid, remote_address: '203.0.113.42', created_at: Time.zone.now },
        { auditable_id: admin.id, auditable_type: 'User', user_id: admin.id, user_type: 'User',
          username: admin.email, action: 'sign_out', associated_id: account.id, associated_type: 'Account',
          version: 2, request_uuid: SecureRandom.uuid, remote_address: '203.0.113.42', created_at: Time.zone.now }
      ]
    )

    get "/api/v1/accounts/#{account.id}/audit_logs", params: { types: ['User'] },
                                                     headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    rows = response.parsed_body['audit_logs'].select { |r| r['auditable_type'] == 'User' }
    expect(rows.map { |r| r['action'] }).to contain_exactly('sign_in', 'sign_out')
    expect(rows.map { |r| r['username'] }.uniq).to eq([admin.email])
    # masked, because the account does not have audit_log_ip_address
    expect(rows.map { |r| r['remote_address'] }.uniq).to eq(['203.0.113.x'])
  end

  it 'masks the address unless the account has audit_log_ip_address' do
    row = Custom::AuditLog.new(remote_address: '203.0.113.42')
    expect(row.masked_remote_address).to eq('203.0.113.x')
    expect(Custom::AuditLog.new(remote_address: '2001:db8:85a3:8d3::1').masked_remote_address)
      .to eq('2001:0db8:85a3:08d3::')
    expect(Custom::AuditLog.new(remote_address: 'garbage').masked_remote_address).to be_nil
    expect(Custom::AuditLog.new(remote_address: nil).masked_remote_address).to be_nil
  end
end
