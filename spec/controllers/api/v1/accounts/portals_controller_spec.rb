require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Portals', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_1) { create(:user, account: account, role: :agent) }
  let(:agent_2) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, slug: 'portal-1', name: 'test_portal', account_id: account.id) }

  describe 'GET /api/v1/accounts/{account.id}/portals' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/portals"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/portals/{portal.slug}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/portals"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'returns not found for a slug that does not exist' do
        get "/api/v1/accounts/#{account.id}/portals/nonexistent-slug",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq 'Resource could not be found'
      end

      it 'returns not found for a slug that belongs to another account' do
        other_portal = create(:portal)

        get "/api/v1/accounts/#{account.id}/portals/#{other_portal.slug}",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/portals' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals",
             params: {},
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/portals/{portal.slug}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/portals/#{portal.slug}", params: {}

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/portals/{portal.slug}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Portal members endpoint removed

  describe 'DELETE /api/v1/accounts/{account.id}/portals/{portal.slug}/logo' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/logo"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      before do
        portal.logo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      end

      it 'throw error if agent' do
        delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/logo",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/portals/{portal.slug}/send_instructions' do
    let(:portal_with_domain) { create(:portal, slug: 'portal-with-domain', account_id: account.id, custom_domain: 'docs.example.com') }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals/#{portal_with_domain.slug}/send_instructions",
             params: { email: 'dev@example.com' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals/#{portal_with_domain.slug}/send_instructions",
             headers: agent.create_new_auth_token,
             params: { email: 'dev@example.com' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Lynomia owns the documentation; a tenant has no Help Center of its own, so every authoring verb is refused for
  # an administrator as much as for an agent (custom/app/policies/custom/portal_policy.rb). The cross-role matrix is
  # in spec/requests/custom/tenant_help_center_removal_spec.rb.
  describe 'tenant portal authoring' do
    let(:base) { "/api/v1/accounts/#{account.id}/portals" }
    let(:headers) { admin.create_new_auth_token }

    context 'when listing portals' do
      let(:perform_request) { get base, headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when reading one portal' do
      let(:perform_request) { get "#{base}/#{portal.slug}", headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when creating a portal' do
      let(:perform_request) do
        post base, params: { name: 'new portal', slug: 'new-portal' }, headers: headers, as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when updating a portal' do
      let(:perform_request) do
        patch "#{base}/#{portal.slug}", params: { name: 'renamed' }, headers: headers, as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when deleting a portal' do
      let(:perform_request) { delete "#{base}/#{portal.slug}", headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when archiving a portal' do
      let(:perform_request) { patch "#{base}/#{portal.slug}/archive", headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when removing a portal logo' do
      let(:perform_request) { delete "#{base}/#{portal.slug}/logo", headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when sending portal instructions' do
      let(:perform_request) do
        post "#{base}/#{portal.slug}/send_instructions", params: { email: 'dev@example.com' }, headers: headers,
                                                         as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'
    end
  end
end
