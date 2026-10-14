require 'rails_helper'

# A bearer credential an integration may hold on a merchant's behalf, and the boundary it keeps.
#
# THE DEFECT THIS EXISTS FOR, measured before the account_id column: a User's personal access token
# reached EVERY account that user belonged to. The Phase 1 account scope could not see it, because
# that scope is read from users.tokens[client] and the api_access_token path never sets @token --
# so it resolved to nil, and nil means unscoped. An integration granted one workspace held them all.
RSpec.describe 'Scoped access tokens', type: :request do
  let(:platform_app) { create(:platform_app) }
  let(:headers) { { api_access_token: platform_app.access_token.token } }

  let(:linked) { create(:account) }
  let(:elsewhere) { create(:account) }
  # One person in two workspaces: the ordinary case, and the reason an unscoped token was a hole.
  let(:user) { create(:user, account: linked, role: :agent) }

  before do
    elsewhere.account_users.create!(user: user, role: :agent)
    create(:platform_app_permissible, platform_app: platform_app, permissible: linked)
    create(:platform_app_permissible, platform_app: platform_app, permissible: user)
  end

  def mint(account_id: linked.id, **params)
    post "/platform/api/v1/users/#{user.id}/scoped_access_token",
         params: { account_id: account_id }.merge(params), headers: headers, as: :json
    response.parsed_body['token']
  end

  describe 'minting' do
    it 'returns a token bound to the account and carrying an expiry' do
      mint

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['account_id']).to eq(linked.id)
      expect(body['token']).to be_present
      expect(Time.zone.parse(body['expires_at'])).to be_between(6.days.from_now, 8.days.from_now)
    end

    it 'refuses an account the app does not hold' do
      post "/platform/api/v1/users/#{user.id}/scoped_access_token",
           params: { account_id: elsewhere.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(user.scoped_access_tokens).to be_empty
    end

    it 'refuses an account the user is not a member of' do
      stranger = create(:account)
      create(:platform_app_permissible, platform_app: platform_app, permissible: stranger)

      post "/platform/api/v1/users/#{user.id}/scoped_access_token",
           params: { account_id: stranger.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses a user the app does not hold at all' do
      stranger = create(:user, account: linked, role: :agent)

      post "/platform/api/v1/users/#{stranger.id}/scoped_access_token",
           params: { account_id: linked.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # A caller refilling a cache must not invalidate the copy another of its own processes holds.
    it 'returns the same live token rather than rotating it' do
      first = mint
      second = mint

      expect(second).to eq(first)
      expect(user.scoped_access_tokens.where(account_id: linked.id).count).to eq(1)
    end

    it 'replaces a lapsed token instead of accumulating rows' do
      mint
      user.scoped_access_tokens.first.update!(expires_at: 1.hour.ago)

      replacement = mint

      expect(user.scoped_access_tokens.where(account_id: linked.id).count).to eq(1)
      expect(replacement).to be_present
    end

    it 'clamps an absurd lifespan rather than honouring it' do
      mint(expires_in_seconds: 10.years.to_i)

      expect(Time.zone.parse(response.parsed_body['expires_at'])).to be < 31.days.from_now
    end
  end

  describe 'what the token can reach' do
    it 'reaches the account it was scoped to' do
      token = mint

      get "/api/v1/accounts/#{linked.id}/conversations", headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:success)
    end

    # THE WHOLE POINT. The same request with the user's PERSONAL token answers 200.
    it 'cannot reach another account the same person belongs to' do
      token = mint

      get "/api/v1/accounts/#{elsewhere.id}/conversations", headers: { api_access_token: token }, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/accounts/#{elsewhere.id}/contacts", headers: { api_access_token: token }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    # Pinned deliberately: it is the behaviour the scoped token exists to avoid, and if it ever
    # changes the comment above stops being true.
    it 'documents that the personal token is still unscoped, which is why this one exists' do
      get "/api/v1/accounts/#{elsewhere.id}/conversations",
          headers: { api_access_token: user.access_token.token }, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'is refused once it has expired' do
      token = mint
      user.scoped_access_tokens.first.update!(expires_at: 1.second.ago)

      get "/api/v1/accounts/#{linked.id}/conversations", headers: { api_access_token: token }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'cannot be widened by anything the caller sends' do
      token = mint

      get "/api/v1/accounts/#{elsewhere.id}/conversations",
          params: { account_id: elsewhere.id },
          headers: { api_access_token: token, account_id: elsewhere.id.to_s }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'backward compatibility' do
    # The personal token is selected by account_id IS NULL. Without that condition has_one would
    # be LIMIT 1 with no ORDER BY over two rows and the profile page would show either one.
    it 'leaves user.access_token pointing at the personal, unscoped token' do
      personal = user.access_token.token
      mint

      expect(user.reload.access_token.token).to eq(personal)
      expect(user.access_token.account_id).to be_nil
    end

    it 'leaves a token with no expiry immortal' do
      expect(user.access_token.expired?).to be(false)
      expect(user.access_token.expires_at).to be_nil
    end

    it 'still lets a platform app use its own token' do
      get '/platform/api/v1/accounts', headers: headers, as: :json

      expect(response).to have_http_status(:success)
    end
  end
end
