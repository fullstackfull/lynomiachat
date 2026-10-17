require 'rails_helper'

RSpec.describe 'Account integration grants API', type: :request do
  include_context 'with account link codes'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:platform_app) { create(:platform_app) }
  let(:path) { "/api/v1/accounts/#{account.id}/integrations/grants" }

  # Link for real rather than hand-building permissibles, so the listing and revocation are exercised
  # against the state the redemption actually produces.
  def link!(app = platform_app)
    code = Integrations::AccountLinkCode.create(account: account, user: admin, platform_app: app)[:code]
    post '/platform/api/v1/account_links', params: { code: code },
                                           headers: { api_access_token: app.access_token.token }, as: :json
    expect(response).to have_http_status(:created)
  end

  # One Lynomia identity for one person in this workspace, as the integration creates them: its own user,
  # a member of this account only, granted to the app so it can mint that person a scoped SSO link.
  def identity_for(name, app: platform_app, role: :agent, in_account: account)
    user = create(:user, account: in_account, role: role, name: name)
    create(:platform_app_permissible, platform_app: app, permissible: user)
    user
  end

  describe 'GET' do
    it 'lists what this workspace has given away, and who the integration signs in as' do
      link!
      identity = identity_for('Merchant Staff')

      get path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      grant = response.parsed_body['grants'].sole
      expect(grant).to include('platform_app_id' => platform_app.id, 'platform_app_name' => platform_app.name)
      expect(grant['signs_in_as'].map { |u| u['id'] }).to eq([identity.id])
      expect(grant['granted_at']).to be_present
    end

    it 'offers the integrations a code may be minted for' do
      mine = platform_app # lazy; force it into existence before the listing is read.
      other = create(:platform_app)

      get path, headers: admin.create_new_auth_token, as: :json

      ids = response.parsed_body['platform_apps'].map { |a| a['id'] }
      expect(ids).to include(mine.id, other.id)
    end

    # A PlatformApp owns an AccessToken through AccessTokenable. Rendering one here would hand a merchant a
    # credential that reaches every OTHER account the app holds.
    it 'never renders an integration access token' do
      link!
      identity_for('Merchant Staff')

      get path, headers: admin.create_new_auth_token, as: :json

      expect(response.body).not_to include(platform_app.access_token.token)
    end

    it 'does not reveal users from other accounts the integration also holds' do
      elsewhere = create(:account)
      elsewhere_admin = create(:user, account: elsewhere, role: :administrator)
      elsewhere_code = Integrations::AccountLinkCode.create(account: elsewhere, user: elsewhere_admin,
                                                            platform_app: platform_app)[:code]
      post '/platform/api/v1/account_links', params: { code: elsewhere_code },
                                             headers: { api_access_token: platform_app.access_token.token },
                                             as: :json
      elsewhere_identity = identity_for('Their Staff', in_account: elsewhere)

      link!
      mine = identity_for('My Staff')

      get path, headers: admin.create_new_auth_token, as: :json

      shown = response.parsed_body['grants'].sole['signs_in_as'].map { |u| u['id'] }
      expect(shown).to eq([mine.id])
      expect(shown).not_to include(elsewhere_identity.id)
    end

    it 'is refused to an agent, and to an administrator of another account' do
      get path, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      outsider = create(:user, account: create(:account), role: :administrator)
      get path, headers: outsider.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'is refused without a session' do
      get path, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE' do
    # The whole reason this surface exists: until now a grant could only be withdrawn by the app holding it,
    # which is the least likely party to volunteer.
    it 'lets the merchant take an integration access back' do
      link!
      service_user = identity_for('Merchant Staff')
      expect(platform_app.platform_app_permissibles.exists?(permissible: account)).to be(true)

      delete "#{path}/#{platform_app.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(platform_app.platform_app_permissibles.exists?(permissible: account)).to be(false)
      expect(platform_app.platform_app_permissibles.exists?(permissible: service_user)).to be(false)

      get "/platform/api/v1/users/#{service_user.id}/login",
          headers: { api_access_token: platform_app.access_token.token }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'kills an SSO link the integration had already minted' do
      link!
      service_user = identity_for('Merchant Staff')
      get "/platform/api/v1/users/#{service_user.id}/login",
          headers: { api_access_token: platform_app.access_token.token }, as: :json
      token = CGI.parse(URI.parse(response.parsed_body['url']).query)['sso_auth_token'].first
      expect(service_user.reload.valid_sso_auth_token?(token)).to be(true)

      delete "#{path}/#{platform_app.id}", headers: admin.create_new_auth_token, as: :json

      expect(service_user.reload.valid_sso_auth_token?(token)).to be(false)
    end

    it 'is idempotent' do
      link!

      delete "#{path}/#{platform_app.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      delete "#{path}/#{platform_app.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'cannot revoke a grant on another account' do
      elsewhere = create(:account)
      elsewhere_admin = create(:user, account: elsewhere, role: :administrator)
      elsewhere_code = Integrations::AccountLinkCode.create(account: elsewhere, user: elsewhere_admin,
                                                            platform_app: platform_app)[:code]
      post '/platform/api/v1/account_links', params: { code: elsewhere_code },
                                             headers: { api_access_token: platform_app.access_token.token },
                                             as: :json
      link!

      # An administrator of THIS account revoking THIS account's grant must not touch the other one.
      delete "#{path}/#{platform_app.id}", headers: admin.create_new_auth_token, as: :json

      expect(platform_app.platform_app_permissibles.exists?(permissible: account)).to be(false)
      expect(platform_app.platform_app_permissibles.exists?(permissible: elsewhere)).to be(true)
    end

    it 'is refused to an agent, and to an administrator of another account' do
      link!

      delete "#{path}/#{platform_app.id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      outsider = create(:user, account: create(:account), role: :administrator)
      delete "#{path}/#{platform_app.id}", headers: outsider.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      expect(platform_app.platform_app_permissibles.exists?(permissible: account)).to be(true)
    end

    it 'records the merchant as the actor on the audit trail' do
      link!

      delete "#{path}/#{platform_app.id}", headers: admin.create_new_auth_token, as: :json

      log = Custom::AuditLog.where(associated: account, comment: 'integrations.account_link.revoked').last
      expect(log.user_id).to eq(admin.id)
      expect(log.audited_changes['platform_app_id']).to eq(platform_app.id)
    end
  end
end
