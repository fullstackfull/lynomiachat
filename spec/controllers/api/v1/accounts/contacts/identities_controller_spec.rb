require 'rails_helper'

# Lynomia unified identity, the API (docs/p10/03-unified-customer-identity.md §6). Reading follows the contact;
# writing follows the merge boundary, because linking a number decides where the next message carrying it goes.
RSpec.describe 'Contact Identities API', type: :request do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/identities" }

  before { account.enable_features('lynomia_unified_identity') && account.save! }

  describe 'GET /identities' do
    before { create(:contact_identity, account: account, contact: contact, identity_type: :phone, value: '+96560000002') }

    it 'returns unauthorized without a session' do
      get base_url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists them for any agent who may open the contact' do
      get base_url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].first).to include('identity_type' => 'phone', 'value' => '+96560000002',
                                                               'source' => 'agent_linked')
    end

    it 'answers not found when the account does not have the feature' do
      account.disable_features('lynomia_unified_identity')
      account.save!

      get base_url, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'does not read another account contact' do
      foreign = create(:contact, account: create(:account))

      get "/api/v1/accounts/#{account.id}/contacts/#{foreign.id}/identities",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /identities' do
    it 'links a number for an administrator' do
      post base_url, params: { identity_type: 'phone', value: '+96560000002' },
                     headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to include('value' => '+96560000002', 'source' => 'agent_linked',
                                                         'linked_by_name' => administrator.name)
      expect(contact.contact_identities.count).to eq(1)
    end

    it 'refuses a plain agent, the same boundary as the merge' do
      post base_url, params: { identity_type: 'phone', value: '+96560000002' },
                     headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(ContactIdentity.count).to eq(0)
    end

    it 'allows an agent whose custom role grants contact management' do
      custom_role = create(:custom_role, account: account, permissions: ['contact_manage'])
      agent.account_users.find_by(account: account).update!(custom_role: custom_role)

      post base_url, params: { identity_type: 'phone', value: '+96560000002' },
                     headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'answers 422 when the value already belongs to another contact, and names it' do
      other = create(:contact, account: account, phone_number: '+96560000002')

      post base_url, params: { identity_type: 'phone', value: '+96560000002' },
                     headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include(other.id.to_s)
    end

    it 'answers 422 for a local number with no country rather than guessing one' do
      post base_url, params: { identity_type: 'phone', value: '0551112233' },
                     headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('country')
    end

    it 'answers 422 for a type the model does not have' do
      post base_url, params: { identity_type: 'passport', value: 'X1234' },
                     headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('phone', 'email')
    end

    it 'is idempotent' do
      2.times do
        post base_url, params: { identity_type: 'email', value: 'dana.alt@example.com' },
                       headers: administrator.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:success)
      expect(contact.contact_identities.count).to eq(1)
    end
  end

  describe 'DELETE /identities/:id' do
    let!(:identity) do
      create(:contact_identity, account: account, contact: contact, identity_type: :phone, value: '+96560000002')
    end

    it 'unlinks it for an administrator' do
      delete "#{base_url}/#{identity.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ContactIdentity.where(id: identity.id)).not_to exist
    end

    it 'refuses a plain agent' do
      delete "#{base_url}/#{identity.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(ContactIdentity.where(id: identity.id)).to exist
    end

    it 'cannot unlink an identity belonging to another contact' do
      other = create(:contact, account: account)
      foreign = create(:contact_identity, account: account, contact: other, identity_type: :phone, value: '+96570000003')

      delete "#{base_url}/#{foreign.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(ContactIdentity.where(id: foreign.id)).to exist
    end
  end
end
