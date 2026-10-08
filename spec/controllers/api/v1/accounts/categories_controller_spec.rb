require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Categories', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:portal) { create(:portal, name: 'test_portal', account_id: account.id, config: { allowed_locales: %w[en es] }) }
  let!(:category) { create(:category, name: 'category', portal: portal, account_id: account.id, slug: 'category_slug', position: 1) }
  let!(:category_to_associate) do
    create(:category, name: 'associated category', portal: portal, account_id: account.id, slug: 'associated_category_slug', position: 2)
  end
  let!(:related_category_1) do
    create(:category, name: 'related category 1', portal: portal, account_id: account.id, slug: 'category_slug_1', position: 3)
  end
  let!(:related_category_2) do
    create(:category, name: 'related category 2', portal: portal, account_id: account.id, slug: 'category_slug_2', position: 4)
  end

  describe 'POST /api/v1/accounts/{account.id}/portals/{portal.slug}/categories' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/portals/{portal.slug}/categories/{category.id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories/#{category.id}", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/portals/{portal.slug}/categories/{category.id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories/#{category.id}", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/portals/{portal.slug}/categories/reorder' do
    let(:positions_hash) do
      {
        category.id => 40,
        category_to_associate.id => 10,
        related_category_1.id => 30,
        related_category_2.id => 20
      }
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories/reorder",
             params: { positions_hash: positions_hash }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'returns not found when portal does not exist' do
        post "/api/v1/accounts/#{account.id}/portals/invalid-portal-slug/categories/reorder",
             params: { positions_hash: positions_hash },
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/portals/{portal.slug}/categories' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Lynomia owns the documentation. Categories are also where a portal's locales are managed, so denying them is what
  # removes tenant locale management (custom/app/policies/custom/category_policy.rb).
  describe 'tenant category and locale management' do
    let(:base) { "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories" }
    let(:headers) { admin.create_new_auth_token }

    context 'when listing categories' do
      let(:perform_request) { get base, headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when creating a category in a new locale' do
      let(:perform_request) do
        post base, params: { category: { name: 'new', slug: 'new-cat', locale: 'es' } }, headers: headers, as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when updating a category' do
      let(:perform_request) do
        put "#{base}/#{category.slug}", params: { category: { name: 'renamed' } }, headers: headers, as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when deleting a category' do
      let(:perform_request) { delete "#{base}/#{category.slug}", headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when reordering categories' do
      let(:perform_request) do
        post "#{base}/reorder", params: { positions: { category.id => 2 } }, headers: headers, as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'
    end
  end
end
