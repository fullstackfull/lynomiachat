require 'rails_helper'

RSpec.describe 'Zid OAuth callback', type: :request do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:settings) { "https://app.lynomia.test/app/accounts/#{account.id}/settings/commerce" }
  let(:token_url) { 'https://oauth.zid.sa/oauth/token' }
  let(:profile_url) { 'https://api.zid.sa/v1/managers/account/profile' }
  let(:token_body) { file_fixture('commerce/zid/token.json').read }
  let(:profile_body) { file_fixture('commerce/zid/profile.json').read }
  # "Connect with Zid" as the administrator's browser does it: the state comes back in Zid's redirect, the cookie stays.
  let(:state) do
    post "/api/v1/accounts/#{account.id}/commerce/zid_connection", headers: admin.create_new_auth_token, as: :json
    Rack::Utils.parse_query(URI(response.parsed_body['authorize_url']).query)['state']
  end

  before do
    account.enable_features!('lynomia_commerce')
    stub_request(:post, token_url).to_return(status: 200, body: token_body)
    stub_request(:get, profile_url).to_return(status: 200, body: profile_body)
  end

  it 'exchanges the code server-side, confirms the store with Zid and connects it to the account in the state' do
    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: state }

    expect(response).to redirect_to("#{settings}?zid=connected")
    store = account.commerce_stores.sole
    expect(store).to have_attributes(provider: 'zid', external_store_id: '318001', name: 'متجر الياسمين', base_url: 'https://jasmine.zid.store',
                                     status: 'active', created_by: admin)
    expect(store.credentials).to include('authorization' => 'zid-fixture-authorization-token', 'access_token' => 'zid-fixture-manager-token',
                                         'refresh_token' => 'zid-fixture-refresh-token', 'token_type' => 'Bearer')
    expect(a_request(:post, token_url).with(body: { grant_type: 'authorization_code', code: 'zid-code-1', client_id: '4821',
                                                    client_secret: zid_client_secret,
                                                    redirect_uri: 'https://app.lynomia.test/commerce/zid/callback' })).to have_been_made.once
    expect(a_request(:get, profile_url).with(headers: { 'Authorization' => 'Bearer zid-fixture-authorization-token',
                                                        'X-Manager-Token' => 'zid-fixture-manager-token' })).to have_been_made.once
    expect(Commerce::Zid::WebhookRegistrationJob).to have_been_enqueued.with(store.id)
  end

  it 'stores the tokens only encrypted and never hands them, or the client secret, to the browser or the logs' do
    io = StringIO.new
    loggers = [Rails.logger, ActionController::Base.logger]
    Rails.logger = ActionController::Base.logger = ActiveSupport::Logger.new(io)
    begin
      get '/commerce/zid/callback', params: { code: 'zid-code-1', state: state }
    ensure
      Rails.logger, ActionController::Base.logger = loggers
    end

    raw = Commerce::Store.connection.select_value("SELECT credentials FROM commerce_stores WHERE provider = 'zid'")
    secrets = ['zid-fixture-authorization-token', 'zid-fixture-manager-token', 'zid-fixture-refresh-token', zid_client_secret, 'zid-code-1', state]
    secrets.each do |secret|
      expect(raw).not_to include(secret)
      expect(io.string).not_to include(secret)
      expect(response.location).not_to include(secret)
    end
    expect(io.string).to include('/commerce/zid/callback')
  end

  it 'checks the state before anything else: without a valid one, no code is exchanged and no account is named' do
    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: 'forged' }

    expect(response).to redirect_to('https://app.lynomia.test/app')
    expect(a_request(:post, token_url)).not_to have_been_made
    expect(Commerce::Store.count).to eq(0)
  end

  it 'accepts a state once: a replayed callback changes nothing' do
    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: state }
    get '/commerce/zid/callback', params: { code: 'zid-code-2', state: state }

    expect(response).to redirect_to('https://app.lynomia.test/app')
    expect(a_request(:post, token_url)).to have_been_made.once
  end

  it 'refuses an expired state' do
    issued = state
    travel 11.minutes do
      get '/commerce/zid/callback', params: { code: 'zid-code-1', state: issued }
    end

    expect(response).to redirect_to('https://app.lynomia.test/app')
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'takes the account only from the state, never from query parameters' do
    other = create(:account)
    other.enable_features!('lynomia_commerce')

    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: state, account_id: other.id }

    expect(response).to redirect_to("#{settings}?zid=connected")
    expect(other.commerce_stores).to be_empty
    expect(account.commerce_stores.count).to eq(1)
  end

  it "refuses another browser's callback, such as a state leaked to an agent" do
    issued = state
    cookies.delete('lynomia_zid_oauth')

    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: issued }

    expect(response).to redirect_to('https://app.lynomia.test/app')
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'refuses a user who is no longer an administrator when the callback arrives' do
    issued = state
    admin.account_users.find_by!(account: account).update!(role: :agent)

    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: issued }

    expect(response).to redirect_to("#{settings}?zid_error=PERMISSION_DENIED")
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'refuses when the account lost Commerce in the meantime' do
    issued = state
    account.disable_features!('lynomia_commerce')

    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: issued }

    expect(response).to redirect_to("#{settings}?zid_error=PERMISSION_DENIED")
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'refuses when the installation switched Zid off in the meantime' do
    issued = state
    InstallationConfig.find_by!(name: 'ZID_ENABLED').update!(value: false)
    GlobalConfig.clear_cache

    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: issued }

    expect(response).to redirect_to("#{settings}?zid_error=PROVIDER_DISABLED")
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'saves nothing when the merchant declines on Zid' do
    get '/commerce/zid/callback', params: { error: 'access_denied', state: state }

    expect(response).to redirect_to("#{settings}?zid_error=AUTH_INVALID")
    expect(a_request(:post, token_url)).not_to have_been_made
  end

  it 'saves nothing when Zid rejects the code' do
    stub_request(:post, token_url).to_return(status: 400, body: '{"error":"invalid_grant"}')

    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: state }

    expect(response).to redirect_to("#{settings}?zid_error=AUTH_INVALID")
    expect(Commerce::Store.count).to eq(0)
  end

  it 'saves nothing when the store cannot be verified with Zid' do
    stub_request(:get, profile_url).to_return(status: 200, body: { user: { store: { title: 'No id' } } }.to_json)

    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: state }

    expect(response).to redirect_to("#{settings}?zid_error=INVALID_RESPONSE")
    expect(Commerce::Store.count).to eq(0)
  end

  it 'never moves a store that another account has connected' do
    connected = create(:commerce_store, :zid, external_store_id: '318001')

    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: state }

    expect(response).to redirect_to("#{settings}?zid_error=STORE_ALREADY_CONNECTED")
    expect(connected.reload).to have_attributes(account_id: connected.account_id, status: 'active')
    expect(connected.credentials['authorization']).to eq('zid-authorization-factory')
  end

  it "re-authorizes the account's own store in place with the new tokens" do
    store = create(:commerce_store, :zid, account: account, external_store_id: '318001', status: :needs_reauth)

    get '/commerce/zid/callback', params: { code: 'zid-code-1', state: state }

    expect(response).to redirect_to("#{settings}?zid=connected")
    expect(account.commerce_stores.sole).to eq(store)
    expect(store.reload).to have_attributes(status: 'active')
    expect(store.credentials['authorization']).to eq('zid-fixture-authorization-token')
  end
end
