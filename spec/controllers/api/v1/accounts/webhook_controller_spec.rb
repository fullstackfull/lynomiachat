require 'rails_helper'

RSpec.describe 'Webhooks API', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:webhook) { create(:webhook, account: account, inbox: inbox, url: 'https://hello.com', name: 'My Webhook') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/<account_id>/webhooks' do
    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/webhooks",
            headers: agent.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin user' do
      it 'gets all webhook' do
        get "/api/v1/accounts/#{account.id}/webhooks",
            headers: administrator.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload']['webhooks'].count).to eql account.webhooks.count
      end
    end

    context 'when api_and_webhooks feature is disabled' do
      it 'allows session authenticated admins to manage webhooks' do
        allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
        account.disable_features!('api_and_webhooks')
        get "/api/v1/accounts/#{account.id}/webhooks",
            headers: administrator.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'POST /api/v1/accounts/<account_id>/webhooks' do
    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             headers: agent.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin user' do
      it 'creates webhook' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { account_id: account.id, inbox_id: inbox.id, url: 'https://hello.com' },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:success)

        expect(response.parsed_body['payload']['webhook']['url']).to eql 'https://hello.com'
      end

      it 'creates webhook with name' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { account_id: account.id, inbox_id: inbox.id, url: 'https://hello.com', name: 'My Webhook' },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:success)

        expect(response.parsed_body['payload']['webhook']['name']).to eql 'My Webhook'
      end

      it 'throws error when invalid url provided' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { account_id: account.id, inbox_id: inbox.id, url: 'javascript:alert(1)' },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to eql 'Url is invalid'
      end

      it 'throws error if subscription events are invalid' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { url: 'https://hello.com', subscriptions: ['conversation_random_event'] },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to eql 'Subscriptions Invalid events'
      end

      it 'throws error if subscription events are empty' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { url: 'https://hello.com', subscriptions: [] },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to eql 'Subscriptions Invalid events'
      end

      it 'use default if subscription events are nil' do
        post "/api/v1/accounts/#{account.id}/webhooks",
             params: { url: 'https://hello.com', subscriptions: nil },
             headers: administrator.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:ok)
        expect(
          response.parsed_body['payload']['webhook']['subscriptions']
        ).to eql %w[conversation_status_changed conversation_updated conversation_created contact_created contact_updated
                    message_created message_updated webwidget_triggered]
      end
    end
  end

  describe 'PUT /api/v1/accounts/<account_id>/webhooks/:id' do
    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
            headers: agent.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin user' do
      it 'updates webhook' do
        put "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
            params: { url: 'https://hello.com', name: 'Another Webhook' },
            headers: administrator.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload']['webhook']['url']).to eql 'https://hello.com'
        expect(response.parsed_body['payload']['webhook']['name']).to eql 'Another Webhook'
      end
    end
  end

  describe 'DELETE /api/v1/accounts/<account_id>/webhooks/:id' do
    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
               headers: agent.create_new_auth_token,
               as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin user' do
      it 'deletes webhook' do
        delete "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
               headers: administrator.create_new_auth_token,
               as: :json
        expect(response).to have_http_status(:success)
        expect(account.webhooks.count).to be 0
      end
    end
  end

  # A RECEIVER MAY CHOOSE ITS SIGNING KEY, AND MAY NOT MOVE IT AFTERWARDS.
  #
  # Permitting :secret on every action, which is how this started, silently broke two controls
  # that are both written against "this column cannot change once the row exists":
  # Custom::Audit::Webhook audits only five configuration columns, so an update touching ONLY the
  # secret writes NO audit row at all; and lib/webhooks/trigger.rb signs only when the secret is
  # present, with nothing validating presence, so one PATCH with an empty string would unsign
  # every future delivery for that webhook. Neither fails loudly. These pin the boundary instead.
  describe 'the signing secret' do
    it 'is accepted on create, so a receiver can derive its own key' do
      post "/api/v1/accounts/#{account.id}/webhooks",
           params: { webhook: { url: 'https://chosen.example/hook', subscriptions: ['conversation_created'],
                                secret: 'receiver-derived-key' } },
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.webhooks.find_by(url: 'https://chosen.example/hook').secret).to eq('receiver-derived-key')
    end

    it 'is generated when the caller does not choose one' do
      post "/api/v1/accounts/#{account.id}/webhooks",
           params: { webhook: { url: 'https://generated.example/hook', subscriptions: ['conversation_created'] } },
           headers: administrator.create_new_auth_token, as: :json

      expect(account.webhooks.find_by(url: 'https://generated.example/hook').secret).to be_present
    end

    # The one that matters: a delivery that stops being signed is not an error anywhere.
    it 'cannot be blanked, or changed at all, by an update' do
      original = webhook.secret
      expect(original).to be_present

      put "/api/v1/accounts/#{account.id}/webhooks/#{webhook.id}",
          params: { webhook: { secret: '', name: 'Renamed' } },
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(webhook.reload.secret).to eq(original)
      expect(webhook.name).to eq('Renamed')
    end

    # DISCLOSED TO THE ACCOUNT'S OWN ADMINISTRATORS, which is upstream behaviour and is pinned
    # here because a receiver that DERIVES its key needs to know it. An administrator can read
    # the key their own deliveries are signed with, so a per-receiver key is not optional: one
    # global key would hand every administrator the means to forge deliveries for every other
    # account. Deriving it per receiver confines that to their own.
    it 'is readable by an administrator of the account that owns it' do
      webhook
      get "/api/v1/accounts/#{account.id}/webhooks",
          headers: administrator.create_new_auth_token, as: :json

      expect(response.body).to include(webhook.secret)
    end
  end
end
