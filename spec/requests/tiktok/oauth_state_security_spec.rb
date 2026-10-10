require 'rails_helper'

# SC4 of the P10 security closure (docs/p11/00-p10-security-closure.md).
#
# The TikTok OAuth state used to be `{ sub: account_id, iat: }` with `verify_expiration: true` and no
# `required_claims`, which the jwt gem accepts: its expiration verifier returns early when the payload has no
# `exp` key, so presence is never enforced. The state therefore never expired, and it named an account but no
# person, while the callback controller has no authentication of its own. Anyone holding one could complete a
# TikTok connection into that account, indefinitely.
RSpec.describe 'TikTok OAuth state security', type: :request do
  let(:client_secret) { 'tiktok-app-secret' }
  # Most refusals cannot name an account at all. Two can: an account that resolves but whose user or
  # entitlement is wrong.
  let(:resolvable_account) { false }
  let(:client_id) { 'tiktok-app-id' }
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }
  let(:outsider) { create(:user, account: other_account, role: :administrator) }

  def state_for(account_id:, user_id:, expires_in: 10.minutes, omit: [])
    issued_at = Time.current.to_i
    payload = { sub: account_id, uid: user_id, iat: issued_at, exp: issued_at + expires_in.to_i }
    payload = payload.except(*omit)
    JWT.encode(payload, client_secret, 'HS256')
  end

  def call_back_with(state)
    with_modified_env TIKTOK_APP_ID: client_id, TIKTOK_APP_SECRET: client_secret do
      get '/tiktok/callback', params: { code: 'valid_code', state: state }
    end
  end

  before do
    account.enable_features!('channel_tiktok')
    InstallationConfig.where(name: %w[TIKTOK_APP_ID TIKTOK_APP_SECRET]).delete_all
    GlobalConfig.clear_cache
  end

  # If the state is refused, the code must never be exchanged. The absence of a WebMock stub for the token
  # endpoint is itself the assertion: any outbound call would raise WebMock::NetConnectNotAllowedError.
  shared_examples 'a refused state' do
    it 'creates nothing and does not exchange the authorization code' do
      expect { call_back_with(state) }.not_to change(Channel::Tiktok, :count)
      expect(response).to be_redirect
      expect(response.location).to include('error_type=invalid_state')
      # A state that does not verify names no account, so the browser goes to the installation's front door
      # rather than to an account-scoped page that cannot be addressed.
      expect(response.location).not_to include('settings/inboxes/new/tiktok') unless resolvable_account
    end
  end

  context 'when the state carries no exp claim, as every state did before this change' do
    let(:state) { state_for(account_id: account.id, user_id: administrator.id, omit: [:exp]) }

    it_behaves_like 'a refused state'
  end

  context 'when the state has expired' do
    let(:state) { state_for(account_id: account.id, user_id: administrator.id, expires_in: -1.minute) }

    it_behaves_like 'a refused state'
  end

  context 'when the state names no user, as every state did before this change' do
    let(:state) { state_for(account_id: account.id, user_id: nil, omit: [:uid]) }

    it_behaves_like 'a refused state'
  end

  context 'when the state names a user who is not a member of the account it names' do
    let(:resolvable_account) { true }

    let(:state) { state_for(account_id: account.id, user_id: outsider.id) }

    it_behaves_like 'a refused state'
  end

  context 'when the state names a member of the account who is not an administrator' do
    let(:resolvable_account) { true }

    let(:state) { state_for(account_id: account.id, user_id: agent.id) }

    it_behaves_like 'a refused state'
  end

  context 'when the state is signed with the wrong secret' do
    let(:state) do
      issued_at = Time.current.to_i
      JWT.encode({ sub: account.id, uid: administrator.id, iat: issued_at, exp: issued_at + 600 }, 'not-the-secret', 'HS256')
    end

    it_behaves_like 'a refused state'
  end

  context 'when the state names an account that does not exist' do
    let(:state) { state_for(account_id: 0, user_id: administrator.id) }

    it_behaves_like 'a refused state'
  end

  context 'when the entitlement was revoked between minting the state and the callback' do
    let(:resolvable_account) { true }

    let(:state) { state_for(account_id: account.id, user_id: administrator.id) }

    before { account.disable_features!('channel_tiktok') }

    it_behaves_like 'a refused state'
  end

  # An earlier draft here asserted that a state naming a foreign account is answered identically to an
  # expired one, on existence-leak grounds. It is not, and it does not need to be: a state only reaches this
  # controller if it was signed with the installation's TikTok app secret, which is what the wrong-secret
  # example above covers. Nothing an outsider can produce gets far enough to tell these two cases apart, so
  # the example was asserting a property the design does not have and does not require.
  it 'does not forward a provider response body into the user-visible redirect' do
    stub_request(:post, 'https://business-api.tiktok.com/open_api/v1.3/tt_user/oauth2/token/')
      .to_return(status: 400, body: { code: 40_001, message: 'app_secret ts-9f3a1 is invalid for app_id 777' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    call_back_with(state_for(account_id: account.id, user_id: administrator.id))

    expect(response.location).not_to include('ts-9f3a1')
    expect(response.location).not_to include('app_secret')
    expect(CGI.unescape(response.location)).to include('TikTok could not complete the connection')
  end
end
