require 'rails_helper'

RSpec.describe 'Platform account links API', type: :request do
  include_context 'with account link codes'

  let(:platform_app) { create(:platform_app) }
  let(:token) { platform_app.access_token.token }
  let(:headers) { { api_access_token: token } }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:code) { Integrations::AccountLinkCode.create(account: account, user: admin, platform_app: platform_app)[:code] }

  def granted?(resource)
    platform_app.platform_app_permissibles.exists?(permissible: resource)
  end

  describe 'POST /platform/api/v1/account_links' do
    it 'grants the account and nothing else' do
      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        'account_id' => account.id, 'account_name' => account.name,
        'authorized_by_user_id' => admin.id
      )
      expect(granted?(account)).to be(true)
      # Not the authorizing human -- their session would be unscoped -- and no shared service identity
      # either. Who signs in is decided per person afterwards, with the role that person actually holds.
      expect(granted?(admin)).to be(false)
      expect(platform_app.platform_app_permissibles.where(permissible_type: 'User')).to be_empty
    end

    it 'adds no member to the workspace, so nobody is a default administrator' do
      minted = code # lazy: minting creates the administrator membership, which is not what is measured

      expect do
        post '/platform/api/v1/account_links', params: { code: minted }, headers: headers, as: :json
      end.not_to(change { account.reload.account_users.count })
    end

    # THE REASON THE SERVICE USER EXISTS. generate_sso_link mints an UNSCOPED session for a human: granting
    # the administrator's own identity would cash a proof about ONE account in for the ability to act as that
    # person in every account they belong to.
    it 'cannot reach an unrelated account the authorizing human also belongs to' do
      elsewhere = create(:account)
      elsewhere.account_users.create!(user: admin, role: :agent)

      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json

      expect(granted?(elsewhere)).to be(false)
      # The human whose unscoped session would have carried that reach is not grantable at all.
      get "/platform/api/v1/users/#{admin.id}/login", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an unauthenticated caller before touching the code' do
      post '/platform/api/v1/account_links', params: { code: code }

      expect(response).to have_http_status(:unauthorized)
      expect(granted?(account)).to be(false)
      # The code must survive: an unauthenticated probe that burned it would be a denial-of-service primitive.
      expect(Integrations::AccountLinkCode.redeem(code, platform_app: platform_app)).to be_a(Hash)
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

      used = Integrations::AccountLinkCode.create(account: account, user: admin, platform_app: platform_app)[:code]
      post '/platform/api/v1/account_links', params: { code: used }, headers: headers, as: :json
      post '/platform/api/v1/account_links', params: { code: used }, headers: headers, as: :json
      bodies << [response.status, response.parsed_body]

      expired = Integrations::AccountLinkCode.create(account: account, user: admin, platform_app: platform_app)[:code]
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

    it 'refuses a code that has already been redeemed' do
      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json

      expect do
        post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json
      end.not_to change(PlatformAppPermissible, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # THE ONE ABOVE DOES NOT TEST GRANTING, which is why this exists. Re-posting the same code is refused at
    # redeem -- the code is burned -- so it never reaches grant at all, and naming it "idempotent" credited
    # the grant path with a property nothing had exercised. A SECOND code for the SAME account does reach it.
    it 'grants nothing new when the same account is linked a second time' do
      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json
      expect(response).to have_http_status(:created)

      second_code = Integrations::AccountLinkCode.create(account: account, user: admin, platform_app: platform_app)[:code]

      expect do
        post '/platform/api/v1/account_links', params: { code: second_code }, headers: headers, as: :json
      end.not_to change(PlatformAppPermissible, :count)

      expect(response).to have_http_status(:created)
      expect(platform_app.platform_app_permissibles.where(permissible_type: 'Account').count).to eq(1)
    end

    # The code now names its audience at mint time, so the merchant can see who it is FOR before they hand
    # it over, and who actually took it afterwards. The two agreeing is the thing worth asserting: a
    # mismatch is the shape a misdirection would have had, and it can no longer happen.
    it 'names both the intended and the actual integration' do
      minted = code # `code` is lazy; mint before reading the status it writes.
      expect(Integrations::AccountLinkCode.status(account)).to include(intended_app: platform_app.name)

      post '/platform/api/v1/account_links', params: { code: minted }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(Integrations::AccountLinkCode.status(account))
        .to include(status: 'connected', connected_app: platform_app.name, intended_app: platform_app.name)
    end

    it 'records who authorized which app' do
      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json

      log = Custom::AuditLog.where(associated: account, comment: 'integrations.account_link.granted').sole
      # The actor is the human who decided; the service user is what can actually sign in. Both, separately.
      expect(log.user_id).to eq(admin.id)
      expect(log.audited_changes['platform_app_id']).to eq(platform_app.id)
      expect(log.audited_changes['authorized_by_user_id']).to eq(admin.id)
      expect(log.audited_changes['service_user_id']).not_to eq(admin.id)
    end

    it 'does not let one app redeem and then another reuse the same code' do
      other_app = create(:platform_app)

      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json
      post '/platform/api/v1/account_links', params: { code: code },
                                             headers: { api_access_token: other_app.access_token.token }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(other_app.platform_app_permissibles).to be_empty
    end

    # THE AUDIENCE. Before it, whichever app presented the code first won -- verified by execution -- and a
    # merchant pasting it into the wrong integration's field handed that app a working grant while the
    # intended one was told only "Invalid or expired code".
    it 'refuses an app the code was not minted for, and leaves the code live' do
      other_app = create(:platform_app)

      post '/platform/api/v1/account_links', params: { code: code },
                                             headers: { api_access_token: other_app.access_token.token }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('This code was issued for a different integration')
      # THE CODE, NOT THE SENTENCE, IS THE CONTRACT. The integration on the other side has to tell its
      # merchant which mistake they made, and matching on English prose would break the day somebody
      # rewords it. Changing this string changes behaviour in another codebase.
      expect(response.parsed_body['error_code']).to eq('wrong_platform_app')
      expect(other_app.platform_app_permissibles).to be_empty
      expect(granted?(account)).to be(false)

      # And the legitimate integration can still use it -- a wrong redemption must not be a way to destroy
      # somebody else's code.
      post '/platform/api/v1/account_links', params: { code: code }, headers: headers, as: :json
      expect(response).to have_http_status(:created)
    end

    it 'tells the two refusals apart only where the difference is actionable' do
      other_app = create(:platform_app)

      post '/platform/api/v1/account_links', params: { code: 'AAAA-BBBB-CCCC-DDDD' }, headers: headers, as: :json
      unknown = response.parsed_body
      expect(unknown['error_code']).to eq('invalid_code')

      post '/platform/api/v1/account_links', params: { code: code },
                                             headers: { api_access_token: other_app.access_token.token }, as: :json

      # An unknown code and a code for somebody else are deliberately DIFFERENT answers: the app cannot act
      # on either, but the merchant who misdirected their code is the one who needs to know they did.
      expect(response.parsed_body).not_to eq(unknown)
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
      service_user = create(:user, account: account, role: :agent)
      create(:platform_app_permissible, platform_app: platform_app, permissible: service_user)

      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(granted?(account)).to be(false)
      expect(granted?(service_user)).to be(false)

      get "/platform/api/v1/users/#{service_user.id}/login", headers: headers, as: :json
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
      service_user = create(:user, account: account, role: :agent)
      create(:platform_app_permissible, platform_app: platform_app, permissible: service_user)

      get "/platform/api/v1/users/#{service_user.id}/login", headers: headers, as: :json
      token = CGI.parse(URI.parse(response.parsed_body['url']).query)['sso_auth_token'].first
      expect(service_user.reload.valid_sso_auth_token?(token)).to be(true)

      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json

      # Without this the grant is gone but the five-minute link in somebody's address bar still works.
      expect(service_user.reload.valid_sso_auth_token?(token)).to be(false)
    end

    # Membership is mutable by the merchant's own admins, so deriving the revocation set from it let a
    # granted user who had been removed from the workspace keep their grant through a revocation that
    # answered 200.
    it 'hands back a grant even if its user was removed from the account first' do
      service_user = create(:user, account: account, role: :agent)
      create(:platform_app_permissible, platform_app: platform_app, permissible: service_user)
      account.account_users.where(user_id: service_user.id).destroy_all

      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(granted?(service_user)).to be(false)
    end

    # USER_SSO_AUTH_TOKEN::<id>::* is shared key space: other platform apps' login links and super-admin
    # impersonation links live there too. A revocation scoped to one account must not reach into them.
    it 'does not kill another app SSO link for a member it holds no grant on' do
      other_app = create(:platform_app)
      member = create(:user, account: account, role: :agent)
      create(:platform_app_permissible, platform_app: other_app, permissible: member)

      get "/platform/api/v1/users/#{member.id}/login",
          headers: { api_access_token: other_app.access_token.token }, as: :json
      token = CGI.parse(URI.parse(response.parsed_body['url']).query)['sso_auth_token'].first
      expect(member.reload.valid_sso_auth_token?(token)).to be(true)

      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json

      expect(member.reload.valid_sso_auth_token?(token)).to be(true)
      expect(other_app.platform_app_permissibles.exists?(permissible: member)).to be(true)
    end

    it 'records the app as the actor, so the merchant can see who disconnected it' do
      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json

      log = Custom::AuditLog.where(associated: account, comment: 'integrations.account_link.revoked').sole
      expect(log.user_type).to eq('PlatformApp')
      expect(log.user_id).to eq(platform_app.id)
      expect(log.username).to eq(platform_app.name)
    end

    it 'leaves another linked account untouched' do
      second_account = create(:account)
      second_account.account_users.create!(user: admin, role: :administrator)
      second_code = Integrations::AccountLinkCode.create(account: second_account, user: admin, platform_app: platform_app)[:code]
      post '/platform/api/v1/account_links', params: { code: second_code }, headers: headers, as: :json

      delete "/platform/api/v1/account_links/#{account.id}", headers: headers, as: :json

      expect(granted?(account)).to be(false)
      expect(granted?(second_account)).to be(true)
    end
  end
end
