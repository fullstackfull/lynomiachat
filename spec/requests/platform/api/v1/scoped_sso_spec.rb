require 'rails_helper'

# An SSO session scoped to one account, end to end: mint the link, redeem it the way the browser does, then
# try to reach somewhere else with the credentials it returned.
#
# This is the spec that matters for the whole design. Everything else asserts that a scope was written down;
# these assert that it is enforced on a real request.
RSpec.describe 'Account-scoped SSO', type: :request do
  let(:platform_app) { create(:platform_app) }
  let(:headers) { { api_access_token: platform_app.access_token.token } }

  let(:linked) { create(:account) }
  let(:elsewhere) { create(:account) }
  # One person in two workspaces, which is the ordinary case and the reason an unscoped session was a hole.
  let(:user) { create(:user, account: linked, role: :administrator) }

  before do
    elsewhere.account_users.create!(user: user, role: :administrator)
    create(:platform_app_permissible, platform_app: platform_app, permissible: linked)
    create(:platform_app_permissible, platform_app: platform_app, permissible: user)
  end

  # Redeem the minted link exactly as the browser does, and return the devise_token_auth headers it hands
  # back. Those headers ARE the session; there is no cookie to carry.
  def sign_in_through(url)
    query = CGI.parse(URI.parse(url).query)
    post '/auth/sign_in',
         params: { email: query['email'].first, sso_auth_token: query['sso_auth_token'].first },
         as: :json
    expect(response).to have_http_status(:success)
    response.headers.slice('access-token', 'token-type', 'client', 'expiry', 'uid')
  end

  def mint(account_id: nil)
    params = account_id ? { account_id: account_id } : {}
    get "/platform/api/v1/users/#{user.id}/login", params: params, headers: headers, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['url']
  end

  describe 'a scoped session' do
    it 'reaches the account it was scoped to' do
      session = sign_in_through(mint(account_id: linked.id))

      get "/api/v1/accounts/#{linked.id}/conversations", headers: session, as: :json

      expect(response).to have_http_status(:success)
    end

    # THE DEFECT THIS WHOLE DESIGN EXISTS FOR. Before scoping, the session reached here too.
    it 'cannot reach another account the same person belongs to' do
      session = sign_in_through(mint(account_id: linked.id))

      get "/api/v1/accounts/#{elsewhere.id}/conversations", headers: session, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/accounts/#{elsewhere.id}/contacts", headers: session, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'survives across requests, because the scope is on the token and not in a session' do
      session = sign_in_through(mint(account_id: linked.id))

      3.times do
        get "/api/v1/accounts/#{elsewhere.id}/conversations", headers: session, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      get "/api/v1/accounts/#{linked.id}/conversations", headers: session, as: :json
      expect(response).to have_http_status(:success)
    end

    # The client picks WHICH session with its headers; the server's own row says what that session may do.
    it 'cannot be widened by anything the client sends' do
      session = sign_in_through(mint(account_id: linked.id))

      get "/api/v1/accounts/#{elsewhere.id}/conversations",
          params: { account_id: elsewhere.id, sso_account_id: elsewhere.id },
          headers: session.merge('account_id' => elsewhere.id.to_s), as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'is recorded on the token entry, not in the Rails session' do
      sign_in_through(mint(account_id: linked.id))

      entry = user.reload.tokens.values.find { |t| t['account_scope_id'].present? }
      expect(entry['account_scope_id']).to eq(linked.id)
    end
  end

  # A CHOKEPOINT IS ONLY A CHOKEPOINT IF EVERYTHING GOES THROUGH IT. These three surfaces resolve their own
  # account instead, so each had to be asked separately; a scope enforced in one place and absent in three
  # is a scope the merchant cannot rely on.
  describe 'the surfaces that bypass the account chokepoint' do
    it 'cannot read or update another account through the accounts controller' do
      session = sign_in_through(mint(account_id: linked.id))

      get "/api/v1/accounts/#{elsewhere.id}", headers: session, as: :json
      expect(response).to have_http_status(:unauthorized)

      patch "/api/v1/accounts/#{elsewhere.id}", params: { name: 'renamed' }, headers: session, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(elsewhere.reload.name).not_to eq('renamed')

      get "/api/v1/accounts/#{linked.id}", headers: session, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'cannot change availability in another account through the profile surface' do
      session = sign_in_through(mint(account_id: linked.id))
      membership = elsewhere.account_users.find_by(user_id: user.id)

      post '/api/v1/profile/availability',
           params: { profile: { account_id: elsewhere.id, availability: 'busy' } },
           headers: session, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(membership.reload.availability).not_to eq('busy')
    end

    it 'is not handed the other account in the sign-in payload' do
      url = mint(account_id: linked.id)
      query = CGI.parse(URI.parse(url).query)
      post '/auth/sign_in',
           params: { email: query['email'].first, sso_auth_token: query['sso_auth_token'].first }, as: :json

      ids = response.parsed_body['data']['accounts'].map { |a| a['id'] }
      expect(ids).to eq([linked.id])
      expect(response.body).not_to include(elsewhere.name)
    end

    it 'is not handed the other account when the client revalidates its token' do
      session = sign_in_through(mint(account_id: linked.id))

      get '/auth/validate_token', headers: session, as: :json

      ids = response.parsed_body.dig('payload', 'data', 'accounts').map { |a| a['id'] }
      expect(ids).to eq([linked.id])
    end

    it 'still shows every account to an ordinary unscoped session' do
      session = sign_in_through(mint)

      get '/auth/validate_token', headers: session, as: :json

      ids = response.parsed_body.dig('payload', 'data', 'accounts').map { |a| a['id'] }
      expect(ids).to contain_exactly(linked.id, elsewhere.id)
    end
  end

  describe 'backward compatibility' do
    it 'mints an unscoped link when no account is asked for, as every existing caller does' do
      session = sign_in_through(mint)

      # Unscoped behaves exactly as before: both workspaces reachable.
      get "/api/v1/accounts/#{linked.id}/conversations", headers: session, as: :json
      expect(response).to have_http_status(:success)

      get "/api/v1/accounts/#{elsewhere.id}/conversations", headers: session, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'leaves an ordinary password login unscoped' do
      session = user.create_new_auth_token

      get "/api/v1/accounts/#{elsewhere.id}/conversations", headers: session, as: :json

      expect(response).to have_http_status(:success)
    end

    # A token minted before the payload became JSON is still live for up to five minutes after a deploy.
    it 'still accepts a legacy bare-string token' do
      token = SecureRandom.hex(32)
      Redis::Alfred.setex(format(Redis::RedisKeys::USER_SSO_AUTH_TOKEN, user_id: user.id, token: token),
                          'normal', 5.minutes)

      post '/auth/sign_in', params: { email: user.email, sso_auth_token: token }, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'still reports a legacy impersonation token as an impersonation' do
      token = SecureRandom.hex(32)
      Redis::Alfred.setex(format(Redis::RedisKeys::USER_SSO_AUTH_TOKEN, user_id: user.id, token: token),
                          'impersonation', 5.minutes)

      expect(user.sso_auth_token_impersonation?(token)).to be(true)
    end

    # The regression the review warned about: a JSON payload that kept validating while the impersonation
    # check silently answered false would evict a real merchant's session and hand out a 2-month token.
    it 'still reports a current impersonation token as an impersonation' do
      token = user.generate_sso_auth_token(impersonation: true)

      expect(user.valid_sso_auth_token?(token)).to be(true)
      expect(user.sso_auth_token_impersonation?(token)).to be(true)
    end

    it 'does not mark an ordinary token as an impersonation' do
      token = user.generate_sso_auth_token

      expect(user.sso_auth_token_impersonation?(token)).to be(false)
    end

    # The scope survives devise_token_auth rebuilding the token entry. It only does that when
    # change_headers_on_each_request is true, which it is not -- so without the explicit carry this would
    # pass today and fail silently the day somebody flips a config flag.
    it 'keeps the scope when the auth token is refreshed' do
      sign_in_through(mint(account_id: linked.id))
      client = user.reload.tokens.find { |_, t| t['account_scope_id'].present? }.first

      user.create_new_auth_token(client)

      expect(user.reload.tokens[client]['account_scope_id']).to eq(linked.id)
    end

    it 'pins the config the cheap version of that guarantee rests on' do
      expect(DeviseTokenAuth.change_headers_on_each_request).to be(false)
    end
  end

  describe 'minting a scope' do
    it 'refuses an account the app does not hold' do
      get "/platform/api/v1/users/#{user.id}/login", params: { account_id: elsewhere.id },
                                                     headers: headers, as: :json

      # Refused, NOT silently downgraded to unscoped -- a caller that asked for a boundary and was quietly
      # given none is worse off than one that was told no.
      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an account the user is not a member of' do
      stranger = create(:account)
      create(:platform_app_permissible, platform_app: platform_app, permissible: stranger)

      get "/platform/api/v1/users/#{user.id}/login", params: { account_id: stranger.id },
                                                     headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an account that does not exist' do
      get "/platform/api/v1/users/#{user.id}/login", params: { account_id: 0 }, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
