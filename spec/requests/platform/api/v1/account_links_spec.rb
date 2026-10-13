require 'rails_helper'

RSpec.describe 'Platform account links API', type: :request do
  include_context 'with account link codes'

  let(:platform_app) { create(:platform_app) }
  let(:token) { platform_app.access_token.token }
  let(:headers) { { api_access_token: token } }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:code) { Integrations::AccountLinkCode.create(account: account, user: admin)[:code] }

  def granted?(resource)
    platform_app.platform_app_permissibles.exists?(permissible: resource)
  end

  describe 'POST /platform/api/v1/account_links' do
    it 'grants the account and the authorizing user, and returns both' do
      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        'account_id' => account.id, 'account_name' => account.name,
        'user_id' => admin.id, 'user_name' => admin.name
      )
      expect(granted?(account)).to be(true)
      expect(granted?(admin)).to be(true)
    end

    it 'makes SSO possible for the authorizing user and nobody else' do
      other_admin = create(:user, account: account, role: :administrator)

      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json

      get "/platform/api/v1/users/#{admin.id}/login", headers: headers, as: :json
      expect(response).to have_http_status(:success)

      # A second administrator of the same account did not authorize anything, so the app cannot become them.
      get "/platform/api/v1/users/#{other_admin.id}/login", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an unauthenticated caller before touching the code' do
      post '/platform/api/v1/account_links', params: { code: code }

      expect(response).to have_http_status(:unauthorized)
      expect(granted?(account)).to be(false)
      # The code must survive: an unauthenticated probe that burned it would be a denial-of-service primitive.
      expect(Integrations::AccountLinkCode.redeem(code)).to be_present
    end

    it 'refuses an invalid token' do
      post '/platform/api/v1/account_links', params: { code: code }, headers: { api_access_token: 'nope' }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(granted?(account)).to be(false)
    end

    it 'answers identically for unknown, already-used and expired codes' do
      bodies = []

      post '/platform/api/v1/account_links', params: { code: 'AAAA-BBBB-CCCC-DDDD' }, headers: headers, as: :json
      bodies << [response.status, response.parsed_body]

      used = Integrations::AccountLinkCode.create(account: account, user: admin)[:code]
      post '/platform/api/v1/account_links', params: { code: used }, headers: headers, as: :json
      post '/platform/api/v1/account_links', params: { code: used }, headers: headers, as: :json
      bodies << [response.status, response.parsed_body]

      expired = Integrations::AccountLinkCode.create(account: account, user: admin)[:code]
      travel(Integrations::AccountLinkCode::TTL + 1.minute) do
        post '/platform/api/v1/account_links', params: { code: expired }, headers: headers, as: :json
      end
      bodies << [response.status, response.parsed_body]

      expect(bodies.uniq.length).to eq(1)
      expect(bodies.first.first).to eq(422)
    end

    it 'rejects a missing code as 422 rather than a bare 400' do
      post '/platform/api/v1/account_links', params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # The reason the role is re-read at redemption instead of trusted from the code: a code lives an hour, and
    # a dismissal inside that hour has to count.
    it 'refuses a code whose author was demoted after minting it' do
      minted = code
      account.account_users.find_by(user_id: admin.id).update!(role: :agent)

      post '/platform/api/v1/account_links', params: { code: minted }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(granted?(account)).to be(false)
      expect(granted?(admin)).to be(false)
    end

    it 'refuses a code whose author was removed from the account' do
      minted = code
      account.account_users.find_by(user_id: admin.id).destroy!

      post '/platform/api/v1/account_links', params: { code: minted }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(granted?(account)).to be(false)
    end

    it 'is idempotent when the answer to a first redemption was lost' do
      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json

      expect do
        post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json
      end.not_to change(PlatformAppPermissible, :count)
    end

    it 'records who authorized which app' do
      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json

      log = Custom::AuditLog.where(associated: account, comment: 'integrations.account_link.granted').sole
      expect(log.user_id).to eq(admin.id)
      expect(log.audited_changes['platform_app_id']).to eq(platform_app.id)
    end

    it 'does not let one app redeem and then another reuse the same code' do
      other_app = create(:platform_app)

      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json
      post '/platform/api/v1/account_links', params: { code: code },
                                             headers: { api_access_token: other_app.access_token.token }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(other_app.platform_app_permissibles).to be_empty
    end
  end

  describe 'the account listing a linked app reconciles against' do
    before { post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json }

    it 'narrows to a custom attribute without widening what the app can see' do
      account.update!(custom_attributes: { 'store_syria_store_id' => 42 })
      stranger = create(:account, custom_attributes: { 'store_syria_store_id' => 42 })

      get '/platform/api/v1/accounts', params: { custom_attributes: { store_syria_store_id: 42 } },
                                       headers: headers, as: :json

      ids = response.parsed_body.map { |row| row['id'] }
      expect(ids).to eq([account.id])
      expect(ids).not_to include(stranger.id)
    end

    # THE CONTRACT WITH THE OTHER REPOSITORY, PINNED LITERALLY.
    #
    # Store Syria stamps the store as a JSON NUMBER on create and queries it back as a query
    # STRING -- measured on the wire:
    #   POST /platform/api/v1/accounts {"name":"...","custom_attributes":{"store_syria_store_id":42}}
    #   GET  /platform/api/v1/accounts?custom_attributes[store_syria_store_id]=42
    # so the stored value is the integer 42 and the filter value is "42". A comparison that did
    # not coerce would silently match nothing, and the recovery path that exists to prevent
    # duplicate workspaces would create one every time. The raw query string is written out here
    # rather than built from a params hash, because the hash is this spec's idea of the shape
    # and the string is the other repository's.
    it 'matches a numeric stored attribute against the string the platform sends' do
      account.update!(custom_attributes: { 'store_syria_store_id' => 42 })

      get '/platform/api/v1/accounts?custom_attributes[store_syria_store_id]=42', headers: headers, as: :json

      expect(response.parsed_body.map { |row| row['id'] }).to eq([account.id])
    end

    it 'returns nothing for an attribute no account of this app carries' do
      get '/platform/api/v1/accounts', params: { custom_attributes: { store_syria_store_id: 999 } },
                                       headers: headers, as: :json

      expect(response.parsed_body).to be_empty
    end

    # A grant can outlive the account it points at: nothing deletes the permissible row, so `permissible`
    # resolves to nil. The listing is the recovery path, so it must survive the thing it recovers from.
    it 'survives a grant whose account has been deleted' do
      orphan = create(:account)
      create(:platform_app_permissible, platform_app: platform_app, permissible: orphan)
      orphan.delete

      get '/platform/api/v1/accounts', headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.map { |row| row['id'] }).to contain_exactly(account.id)
    end
  end

  describe 'DELETE /platform/api/v1/account_links/:id' do
    before { post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json }

    it 'hands back every grant on the account, so SSO stops working' do
      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(granted?(account)).to be(false)
      expect(granted?(admin)).to be(false)

      get "/platform/api/v1/users/#{admin.id}/login", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'is idempotent' do
      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json
      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json

      # The second call no longer holds a permissible, so the inherited check refuses it -- which is the
      # correct answer, not an error to work around.
      expect(response).to have_http_status(:unauthorized)
    end

    it 'cannot be used against an account the app does not hold' do
      stranger = create(:account)
      stranger_app = create(:platform_app)
      create(:platform_app_permissible, platform_app: stranger_app, permissible: stranger)

      delete "/platform/api/v1/account_links/#{stranger.id}", headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(stranger_app.platform_app_permissibles.exists?(permissible: stranger)).to be(true)
    end

    it 'kills an SSO link already minted but not yet redeemed' do
      get "/platform/api/v1/users/#{admin.id}/login", headers: headers, as: :json
      token = CGI.parse(URI.parse(response.parsed_body['url']).query)['sso_auth_token'].first
      expect(admin.reload.valid_sso_auth_token?(token)).to be(true)

      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json

      # Without this the grant is gone but the five-minute link in somebody's address bar still works.
      expect(admin.reload.valid_sso_auth_token?(token)).to be(false)
    end

    it 'leaves a shared user reachable for another account the app still holds' do
      second_account = create(:account)
      second_account.account_users.create!(user: admin, role: :administrator)
      second_code = Integrations::AccountLinkCode.create(account: second_account, user: admin)[:code]
      post '/platform/api/v1/account_links', params: { code: second_code }, headers: headers, as: :json

      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json

      expect(granted?(second_account)).to be(true)
      # The user grant is shared between the two links; revoking one must not strand the other.
      get "/platform/api/v1/users/#{admin.id}/login", headers: headers, as: :json
      expect(response).to have_http_status(:success)
    end
  end
end
