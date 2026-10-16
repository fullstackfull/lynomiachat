require 'rails_helper'

RSpec.describe 'Platform Accounts API', type: :request do
  let!(:account) { create(:account) }

  describe 'POST /platform/api/v1/accounts' do
    context 'when it is an unauthenticated platform app' do
      it 'returns unauthorized' do
        post '/platform/api/v1/accounts'
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an invalid platform app token' do
      it 'returns unauthorized' do
        post '/platform/api/v1/accounts', params: { name: 'Test Account' },
                                          headers: { api_access_token: 'invalid' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated platform app' do
      let(:platform_app) { create(:platform_app) }

      it 'creates an account when and its permissible relationship' do
        post '/platform/api/v1/accounts', params: { name: 'Test Account' },
                                          headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Test Account')
        expect(platform_app.platform_app_permissibles.first.permissible.name).to eq('Test Account')
      end

      it 'creates an account with locale' do
        InstallationConfig.where(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').first_or_create!(value: [{ 'name' => 'agent_management',
                                                                                                    'enabled' => true }])
        post '/platform/api/v1/accounts', params: { name: 'Test Account', locale: 'es' },
                                          headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response).to have_http_status(:success)

        json_response = response.parsed_body
        expect(json_response['name']).to eq('Test Account')
        expect(json_response['locale']).to eq('es')
        expect(json_response['features']['agent_management']).to be(true)
      end

      it 'creates an account with feature flags' do
        InstallationConfig.where(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').first_or_create!(value: [{ 'name' => 'inbox_management',
                                                                                                    'enabled' => true },
                                                                                                  { 'name' => 'disable_branding',
                                                                                                    'enabled' => true },
                                                                                                  { 'name' => 'help_center',
                                                                                                    'enabled' => false }])

        post '/platform/api/v1/accounts', params: { name: 'Test Account', features: {
          ip_lookup: true,
          help_center: true,
          disable_branding: false
        } }, headers: { api_access_token: platform_app.access_token.token }, as: :json

        json_response = response.parsed_body
        created_account = Account.find(json_response['id'])
        expect(created_account.enabled_features.keys).to match_array(%w[inbox_management ip_lookup help_center])
        expect(json_response['name']).to include('Test Account')
        expect(json_response['features'].keys).to match_array(%w[inbox_management ip_lookup help_center])
      end

      it 'creates an account with limits settings' do
        post '/platform/api/v1/accounts', params: { name: 'Test Account', limits: { agents: 5, inboxes: 10 } },
                                          headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Test Account')
        expect(response.body).to include('5')
        expect(response.body).to include('10')
      end
    end
  end

  describe 'GET /platform/api/v1/accounts' do
    context 'when it is an unauthenticated platform app' do
      it 'returns unauthorized' do
        get '/platform/api/v1/accounts'
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an invalid platform app token' do
      it 'returns unauthorized' do
        get '/platform/api/v1/accounts', headers: { api_access_token: 'invalid' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated platform app' do
      let(:platform_app) { create(:platform_app) }
      let!(:account1) { create(:account, name: 'Account A') }
      let!(:account2) { create(:account, name: 'Account B') }

      before do
        create(:platform_app_permissible, platform_app: platform_app, permissible: account1)
        create(:platform_app_permissible, platform_app: platform_app, permissible: account2)
      end

      it 'returns all permissible accounts' do
        get '/platform/api/v1/accounts', headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response.size).to eq(2)
        expect(json_response.map { |acc| acc['name'] }).to include('Account A', 'Account B')
      end

      # P6D. THE INSTALLATION'S OWN WORKSPACE IS NEVER LISTED, even though the partner holds a
      # permissible on it -- it has to, to send from it. Without this it appears among the
      # merchants, and the provisioning path that adopts an existing workspace by marker is
      # one missing filter away from adopting it for a store. It is reachable deliberately by
      # id through `show`, which is permissible-checked like everything else.
      it 'never lists a platform-owned workspace among them' do
        platform = create(:account, name: 'Store Syria Platform', platform_owned: true)
        create(:platform_app_permissible, platform_app: platform_app, permissible: platform)

        get '/platform/api/v1/accounts', headers: { api_access_token: platform_app.access_token.token }, as: :json

        names = response.parsed_body.map { |acc| acc['name'] }
        expect(names).to contain_exactly('Account A', 'Account B')
      end

      it 'still answers for it when the partner asks by id' do
        platform = create(:account, name: 'Store Syria Platform', platform_owned: true)
        create(:platform_app_permissible, platform_app: platform_app, permissible: platform)

        get "/platform/api/v1/accounts/#{platform.id}",
            headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response).to have_http_status(:success)
      end

      # BLOCKER B5, FROM THE PRODUCER SIDE. A partner addresses its platform workspace by a
      # configured id somebody typed. Without this field it cannot tell that id landed on its
      # own workspace rather than on a merchant's -- and a partner sending from a merchant's
      # workspace sends over that merchant's WhatsApp channel, with this installation's
      # UTILITY-only gate not applying either, because that gate reads this same flag.
      #
      # Pinned here because removing the line from the jbuilder breaks the RECEIVER and
      # nothing on this side: the consumer refuses every notice (correctly -- absent is "could
      # not say", not "no"), and Lynomia's suite stays green while its partner has gone quiet.
      it 'tells the partner whether the account it asked about is platform-owned' do
        platform = create(:account, name: 'Store Syria Platform', platform_owned: true)
        create(:platform_app_permissible, platform_app: platform_app, permissible: platform)

        get "/platform/api/v1/accounts/#{platform.id}",
            headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response.parsed_body).to include('platform_owned' => true)
      end

      it 'says so when the account the partner asked about is a merchant\'s' do
        get "/platform/api/v1/accounts/#{account1.id}",
            headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response.parsed_body).to include('platform_owned' => false)
      end

      # THE OTHER HALF OF THE RECEIVER'S ANSWER, and it costs nothing because it was already
      # true: an id that is not this app's comes back 401, not with somebody else's row. So of
      # the two ways an operator mistypes the workspace id -- a merchant's account of ours, or
      # an account that is not ours at all -- the flag catches the first and the permissible
      # check catches the second.
      it 'refuses an id this app holds no permissible on' do
        stranger = create(:account, name: 'Somebody else')

        get "/platform/api/v1/accounts/#{stranger.id}",
            headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      # The flag is an OPERATOR's, not a tenant integration's. `permitted_params` omits it, so
      # an app cannot mark its own workspace as the installation's -- which is the only thing
      # that would make the field above worth nothing.
      it 'refuses to let a partner set the flag on itself' do
        patch "/platform/api/v1/accounts/#{account1.id}",
              params: { platform_owned: true },
              headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(account1.reload.platform_owned).to be(false)
      end
    end
  end

  describe 'GET /platform/api/v1/accounts/{account_id}' do
    context 'when it is an unauthenticated platform app' do
      it 'returns unauthorized' do
        get "/platform/api/v1/accounts/#{account.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an invalid platform app token' do
      it 'returns unauthorized' do
        get "/platform/api/v1/accounts/#{account.id}", headers: { api_access_token: 'invalid' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated platform app' do
      let(:platform_app) { create(:platform_app) }

      it 'returns unauthorized when its not a permissible object' do
        get "/platform/api/v1/accounts/#{account.id}", headers: { api_access_token: platform_app.access_token.token }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'shows an account when its permissible object' do
        create(:platform_app_permissible, platform_app: platform_app, permissible: account)

        get "/platform/api/v1/accounts/#{account.id}",
            headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(response.body).to include(account.name)
      end
    end
  end

  describe 'PATCH /platform/api/v1/accounts/{account_id}' do
    context 'when it is an unauthenticated platform app' do
      it 'returns unauthorized' do
        patch "/platform/api/v1/accounts/#{account.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an invalid platform app token' do
      it 'returns unauthorized' do
        patch "/platform/api/v1/accounts/#{account.id}", params: { name: 'Test Account' },
                                                         headers: { api_access_token: 'invalid' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated platform app' do
      let(:platform_app) { create(:platform_app) }

      it 'returns unauthorized when its not a permissible object' do
        patch "/platform/api/v1/accounts/#{account.id}", params: { name: 'Test Account' },
                                                         headers: { api_access_token: platform_app.access_token.token }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'updates an account when its permissible object' do
        create(:platform_app_permissible, platform_app: platform_app, permissible: account)
        account.enable_features!('inbox_management', 'channel_facebook')

        patch "/platform/api/v1/accounts/#{account.id}", params: {
          name: 'Test Account',
          features: {
            ip_lookup: true,
            help_center: true,
            channel_facebook: false
          },
          limits: { agents: 5, inboxes: 10 }
        }, headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response).to have_http_status(:success)
        account.reload
        expect(account.name).to eq('Test Account')
        expect(account.enabled_features.keys).to match_array(%w[inbox_management ip_lookup help_center])
        expect(account.enabled_features['channel_facebook']).to be_nil
        expect(account.limits['agents']).to eq(5)
        expect(account.limits['inboxes']).to eq(10)
      end
    end
  end

  describe 'DELETE /platform/api/v1/accounts/{account_id}' do
    context 'when it is an unauthenticated platform app' do
      it 'returns unauthorized' do
        delete "/platform/api/v1/accounts/#{account.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an invalid platform app token' do
      it 'returns unauthorized' do
        delete "/platform/api/v1/accounts/#{account.id}", headers: { api_access_token: 'invalid' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated platform app' do
      let(:platform_app) { create(:platform_app) }

      it 'returns unauthorized when its not a permissible object' do
        delete "/platform/api/v1/accounts/#{account.id}", headers: { api_access_token: platform_app.access_token.token }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'destroys the object' do
        create(:platform_app_permissible, platform_app: platform_app, permissible: account)
        expect(DeleteObjectJob).to receive(:perform_later).with(account).once
        delete "/platform/api/v1/accounts/#{account.id}",
               headers: { api_access_token: platform_app.access_token.token }, as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end
end
