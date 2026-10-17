require 'rails_helper'

# THE MANUAL STEP THIS ENDPOINT REMOVES, ASSERTED AS REMOVED.
#
# Until now a `storesyria` store could only be connected through
# Api::V1::Accounts::Commerce::StoresController#create: a browser session, an account
# ADMINISTRATOR, and the `lsc_` token pasted into a form field. So every merchant's orders
# reached their inbox by way of a partner operator minting a token and a human pasting it in.
#
# What the examples below pin is not the happy path -- that is one of them -- but the refusals
# that make the happy path safe to offer: a credential that names another store, a store another
# account holds, an account the app was never granted, an account whose plan does not sell
# commerce, and a repeat that must not become a second installation.
RSpec.describe 'Platform Commerce Installation API', type: :request do
  include_context 'with commerce encryption'

  let!(:partner_app) { create(:platform_app) }
  let!(:account) { create(:account) }
  let(:url) { "/platform/api/v1/accounts/#{account.id}/commerce_installation" }
  let(:headers) { { api_access_token: partner_app.access_token.token } }
  let(:body) { response.parsed_body }
  let(:token) { "lsc_26_3_#{'a' * 64}" }
  let(:external_id) { 'storesyria.test:26' }
  let(:payload) do
    { provider: 'storesyria', external_store_id: external_id,
      base_url: 'https://storesyria.test', commerce_token: token, name: 'al atalssian' }
  end

  before do
    create(:platform_app_permissible, platform_app: partner_app, permissible: account)
    account.enable_features!('lynomia_commerce')
    GlobalConfig.clear_cache
    create(:installation_config, name: 'STORESYRIA_ENABLED', value: true)
    GlobalConfig.clear_cache
    allow(Resolv).to receive(:getaddresses).with('storesyria.test').and_return(['93.184.216.70'])
  end

  # The partner's commerce identity endpoint: the only thing that decides which store a
  # credential is for. `answers` is what Store Syria says the presented token resolves to.
  def stub_identity(answers: external_id, status: 200)
    stub_request(:get, 'https://storesyria.test/api/lynomia/commerce/v1/store')
      .to_return(status: status,
                 body: { external_store_id: answers, name: 'al atalssian' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def install(overrides = {})
    put url, params: payload.merge(overrides), headers: headers
  end

  describe 'authorization' do
    it 'refuses a caller with no token' do
      put url, params: payload

      expect(response).to have_http_status(:unauthorized)
      expect(Commerce::Store.count).to eq(0)
    end

    # A user's own access token is not a platform app token, and the base class is what tells
    # them apart. Pinned here because this endpoint attaches stores.
    it 'refuses a token that is not a platform app' do
      put url, params: payload, headers: { api_access_token: create(:user).access_token.token }

      expect(response).to have_http_status(:unauthorized)
      expect(Commerce::Store.count).to eq(0)
    end

    it 'refuses an account this app was never granted' do
      other = create(:account)
      other.enable_features!('lynomia_commerce')

      put "/platform/api/v1/accounts/#{other.id}/commerce_installation", params: payload, headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(other.commerce_stores.count).to eq(0)
    end

    # Whether an account id exists on this installation is not something an unauthorized caller
    # gets to learn by asking, so the two answers are identical on purpose.
    it 'answers an unknown account exactly as it answers a forbidden one' do
      put '/platform/api/v1/accounts/987654/commerce_installation', params: payload, headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(body['error_code']).to eq('non_permissible_resource')
    end

    # A partner holds a permissible on the installation's own workspace -- it has to, to send
    # from it -- so the permissible check alone does not exclude it.
    it 'refuses the installation own workspace' do
      account.update!(platform_owned: true)

      install

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error_code']).to eq('platform_owned_account')
    end
  end

  describe 'validation at the boundary' do
    it 'refuses a request with no credential' do
      put url, params: payload.except(:commerce_token), headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error_code']).to eq('invalid_request')
    end

    # A token of the wrong shape can never verify, so it is a 422 naming the field rather than a
    # failed health check against the partner.
    it 'refuses a credential of the wrong shape' do
      install(commerce_token: 'not-a-commerce-token')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error_code']).to eq('invalid_request')
    end

    it 'refuses a provider a partner does not install' do
      install(provider: 'woocommerce')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error_code']).to eq('invalid_request')
    end

    it 'refuses a store URL that is not usable' do
      install(base_url: 'http://10.0.0.5')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error_code']).to eq('invalid_store_url')
    end

    it 'refuses the provider when the installation has it switched off' do
      GlobalConfig.clear_cache
      InstallationConfig.find_by(name: 'STORESYRIA_ENABLED').update!(value: false)
      GlobalConfig.clear_cache

      install

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error_code']).to eq('provider_disabled')
    end

    # A store connected into an account without the feature is a row that works and a product
    # that does not: every commerce read path checks it. Refusing is what lets the partner tell
    # its merchant something true.
    it 'refuses an account whose plan does not include commerce' do
      account.disable_features!('lynomia_commerce')

      install

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error_code']).to eq('commerce_disabled')
      expect(account.commerce_stores.count).to eq(0)
    end
  end

  describe 'installing' do
    it 'connects the store and answers with the ids the partner has to record' do
      stub_identity

      install

      expect(response).to have_http_status(:success)
      store = account.commerce_stores.sole
      expect(body).to include('provider' => 'storesyria', 'external_store_id' => external_id,
                              'commerce_store_id' => store.id, 'status' => 'active', 'applied' => true)
      expect(store.credentials).to eq('commerce_token' => token)
      expect(store.name).to eq('al atalssian')
    end

    it 'never echoes the credential back' do
      stub_identity

      install

      expect(response.body).not_to include(token)
    end

    it 'records who installed it' do
      stub_identity

      install

      expect(account.commerce_stores.sole.metadata['installed_by_app']).to eq(partner_app.name)
    end

    # THE OWNERSHIP PROOF, AND THE WHOLE REASON THE DECLARED ID IS PUT ON THE ROW BEFORE THE
    # HEALTH CHECK. The partner declares a store; the credential is then presented back to the
    # partner and the identity that comes back has to be the same store. Without the declared id
    # on the row the adapter would simply TAKE whatever came back -- correct for a merchant
    # pasting their own key into their own account, and not good enough for a partner naming a
    # store on a merchant's behalf.
    it 'refuses a credential that resolves to a different store' do
      stub_identity(answers: 'storesyria.test:99')

      install

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error_code']).to eq('auth_invalid')
      expect(Commerce::Store.count).to eq(0)
    end

    it 'refuses a credential the partner rejects' do
      stub_identity(status: 401)

      install

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Commerce::Store.count).to eq(0)
    end
  end

  describe 'idempotency' do
    before { stub_identity }

    # The partner's activation is a merchant clicking a button and a response that can be lost on
    # the way back, so a repeat has to be a no-op the caller can recognise rather than an error
    # it has to interpret.
    it 'is a successful no-op when the same credential is already installed' do
      install
      expect(body['applied']).to be(true)

      install

      expect(response).to have_http_status(:success)
      expect(body['applied']).to be(false)
      expect(account.commerce_stores.count).to eq(1)
    end

    it 'rotates a credential that has moved' do
      install
      rotated = "lsc_26_4_#{'b' * 64}"

      install(commerce_token: rotated)

      expect(response).to have_http_status(:success)
      expect(body['applied']).to be(true)
      expect(account.commerce_stores.sole.credentials).to eq('commerce_token' => rotated)
    end

    # A token rejected unattended leaves the installation in needs_reauth. Sending a fresh one is
    # exactly the repair, so it is allowed rather than treated as a conflict.
    it 'repairs an installation whose credential was rejected' do
      install
      account.commerce_stores.sole.update!(status: :needs_reauth)

      install(commerce_token: "lsc_26_5_#{'c' * 64}")

      expect(account.commerce_stores.sole).to be_active
      expect(body['applied']).to be(true)
    end

    it 'brings back a store the merchant had disconnected, reusing the same row' do
      install
      store = account.commerce_stores.sole
      Commerce::StoreConnection.new(account: account, user: nil).disconnect(store)

      install

      expect(account.commerce_stores.sole.id).to eq(store.id)
      expect(store.reload).to be_active
    end

    # A STORE AN OPERATOR SWITCHED OFF IS A LYNOMIA DECISION. A partner call that quietly
    # re-enabled it would be a partner reaching across the boundary to undo it, so the state is
    # reported instead and the partner's console can say "suspended" rather than showing a
    # success that contradicts it.
    it 'leaves a store an operator disabled alone, and says so' do
      install
      account.commerce_stores.sole.update!(status: :disabled)

      install

      expect(response).to have_http_status(:success)
      expect(body).to include('status' => 'disabled', 'applied' => false)
      expect(account.commerce_stores.sole).to be_disabled
    end
  end

  describe 'tenancy' do
    it 'refuses a store another account holds' do
      other = create(:account)
      create(:commerce_store, account: other, provider: 'storesyria', external_store_id: external_id,
                              credentials: { 'commerce_token' => token })

      install

      expect(response).to have_http_status(:conflict)
      expect(body['error_code']).to eq('installation_claimed_elsewhere')
      expect(account.commerce_stores.count).to eq(0)
    end

    # It says nothing about WHICH account holds it: the caller is entitled to know it cannot have
    # this store, not to learn about another merchant's workspace.
    it 'does not disclose the holder' do
      other = create(:account, name: 'Someone Else Ltd')
      create(:commerce_store, account: other, provider: 'storesyria', external_store_id: external_id)

      install

      expect(response.body).not_to include('Someone Else Ltd')
      expect(response.body).not_to include(other.id.to_s)
    end

    it 'releases a store another account had disconnected' do
      stub_identity
      other = create(:account)
      dead = create(:commerce_store, account: other, provider: 'storesyria', external_store_id: external_id,
                                     status: :disconnected, credentials: nil)

      install

      expect(response).to have_http_status(:success)
      expect(account.commerce_stores.sole.external_store_id).to eq(external_id)
      expect(Commerce::Store.find_by(id: dead.id)).to be_nil
    end
  end

  describe 'plan limits' do
    # #attach keeps the account inside its plan's `stores` limit, and it must keep doing so when
    # the caller is a partner rather than an administrator.
    it 'refuses to exceed the account store limit' do
      stub_identity
      # Returns the limit that was reached, not a boolean -- which is what #ensure_within_plan!
      # branches on.
      allow(Billing::ResourceLimit).to receive(:exceeded).with(account, :stores).and_return(1)

      install

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.commerce_stores.count).to eq(0)
    end
  end

  describe 'the audit trail' do
    it 'records the connection without the credential' do
      stub_identity

      expect { install }
        .to change { Custom::AuditLog.where(comment: 'commerce.store_connected').count }.by(1)

      entry = Custom::AuditLog.where(comment: 'commerce.store_connected').last
      expect(entry.audited_changes).to include('provider' => 'storesyria', 'external_store_id' => external_id)
      expect(entry.audited_changes.to_s).not_to include(token)
    end
  end
end
