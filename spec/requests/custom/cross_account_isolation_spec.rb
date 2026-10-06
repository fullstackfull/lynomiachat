require 'rails_helper'

# Every tenant-facing endpoint this fork adds, asked for another account's record.
#
# The surfaces Lynomia adds on top of Chatwoot -- the WhatsApp template manager, Commerce stores, the flow builder,
# shared audiences -- each fetch through `Current.account`, which EnsureCurrentAccountHelper sets from the path and
# refuses when the signed-in user is not a member. These prove that from the outside: an administrator of one
# account, holding a real token, cannot read or change the neighbouring account's records, and cannot borrow the
# neighbour's `account_id` either.
#
# Two refusals are distinguished on purpose, because they come from different places and both matter:
#   401 -- the path names an account you are not in. EnsureCurrentAccountHelper, before any record is loaded.
#   404 -- the path names your own account and a record id belonging to someone else. The account-scoped fetch,
#          which must not leak the record's existence.
RSpec.describe 'Cross-account isolation', type: :request do
  let(:account) { create(:account) }
  let(:neighbour) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:neighbour_admin) { create(:user, account: neighbour, role: :administrator) }

  before do
    [account, neighbour].each { |a| a.enable_features!('lynomia_commerce', 'lynomia_flow_builder') }
  end

  describe 'the WhatsApp template manager' do
    let(:neighbour_template) do
      Whatsapp::MessageTemplate.create!(account: neighbour, business_account_id: '1234567890', name: 'order_update',
                                        language: 'en_US', category: 'UTILITY',
                                        components: [{ 'type' => 'BODY', 'text' => 'Hello {{1}}' }], meta_payload: {})
    end

    it 'does not serve, change or delete a template belonging to the neighbouring account' do
      base = "/api/v1/accounts/#{account.id}/whatsapp/message_templates/#{neighbour_template.id}"

      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      patch base, params: { components: [] }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      delete base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      expect(neighbour_template.reload.name).to eq('order_update')
    end

    it 'does not submit or duplicate a template belonging to the neighbouring account' do
      base = "/api/v1/accounts/#{account.id}/whatsapp/message_templates/#{neighbour_template.id}"

      post "#{base}/submit", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      post "#{base}/duplicate", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      expect(Whatsapp::MessageTemplate.where(account: account)).to be_empty
    end

    it 'lists only the account its own path names' do
      neighbour_template

      get "/api/v1/accounts/#{account.id}/whatsapp/message_templates", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to be_empty
    end

    it 'refuses an administrator who reaches for the neighbouring account by id' do
      get "/api/v1/accounts/#{neighbour.id}/whatsapp/message_templates", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an agent of this account, who is not an administrator' do
      get "/api/v1/accounts/#{account.id}/whatsapp/message_templates", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'Commerce stores' do
    let(:neighbour_store) do
      Commerce::Store.create!(account: neighbour, provider: 'woocommerce', name: 'Neighbour shop',
                              base_url: 'https://neighbour.example.com', external_store_id: 'neighbour-1')
    end

    it 'does not change or disconnect a store belonging to the neighbouring account' do
      base = "/api/v1/accounts/#{account.id}/commerce/stores/#{neighbour_store.id}"

      patch base, params: { name: 'Taken over' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      delete base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      expect(neighbour_store.reload.name).to eq('Neighbour shop')
    end

    it 'lists only the account its own path names' do
      neighbour_store

      get "/api/v1/accounts/#{account.id}/commerce/stores", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to be_empty
    end

    it 'refuses an administrator who reaches for the neighbouring account by id' do
      get "/api/v1/accounts/#{neighbour.id}/commerce/stores", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an agent of this account, who is not an administrator' do
      get "/api/v1/accounts/#{account.id}/commerce/stores", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'the flow builder' do
    let(:neighbour_flow) do
      create(:agent_bot, account: neighbour, bot_type: 'flow', name: 'Neighbour flow', outgoing_url: nil)
    end

    it 'does not serve, change, publish or delete a flow belonging to the neighbouring account' do
      base = "/api/v1/accounts/#{account.id}/flows/#{neighbour_flow.id}"

      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      patch base, params: { name: 'Taken over' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      post "#{base}/publish", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      delete base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      expect(neighbour_flow.reload.name).to eq('Neighbour flow')
    end

    it 'lists only the account its own path names' do
      neighbour_flow

      get "/api/v1/accounts/#{account.id}/flows", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to be_empty
    end

    it 'refuses an administrator who reaches for the neighbouring account by id' do
      get "/api/v1/accounts/#{neighbour.id}/flows", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'shared audiences' do
    let(:neighbour_audience) do
      create(:custom_filter, account: neighbour, user: neighbour_admin, filter_type: :contact, shared: true,
                             name: 'Neighbour audience')
    end

    it 'does not serve, change or delete an audience belonging to the neighbouring account' do
      base = "/api/v1/accounts/#{account.id}/custom_filters/#{neighbour_audience.id}"

      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      patch base, params: { custom_filter: { name: 'Taken over' } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      delete base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      expect(neighbour_audience.reload.name).to eq('Neighbour audience')
    end

    it 'lists only the account its own path names' do
      neighbour_audience

      get "/api/v1/accounts/#{account.id}/custom_filters", params: { filter_type: 'contact' },
                                                           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to be_empty
    end

    it 'refuses an administrator who reaches for the neighbouring account by id' do
      get "/api/v1/accounts/#{neighbour.id}/custom_filters", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # An agent may keep personal audiences, so the role boundary here is sharing, not reading.
    it 'refuses an agent who tries to share an audience' do
      post "/api/v1/accounts/#{account.id}/custom_filters",
           params: { custom_filter: { name: 'Everyone', filter_type: 'contact', shared: true, query: { payload: [] } } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
