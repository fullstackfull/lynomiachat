require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Articles', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:portal) { create(:portal, name: 'test_portal', account_id: account.id) }
  let!(:category) { create(:category, name: 'category', portal: portal, account_id: account.id, locale: 'en', slug: 'category_slug') }
  let!(:article) { create(:article, category: category, portal: portal, account_id: account.id, author_id: agent.id) }

  describe 'POST /api/v1/accounts/{account.id}/portals/{portal.slug}/articles' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/portals/{portal.slug}/articles/{article.id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/#{article.id}", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/portals/{portal.slug}/articles/{article.id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/#{article.id}", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/portals/{portal.slug}/articles/reorder' do
    let!(:article_2) do
      create(:article, category: category, portal: portal, account_id: account.id, author_id: agent.id, position: 20)
    end
    let(:positions_hash) do
      {
        article.id => 20,
        article_2.id => 10
      }
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/reorder",
             params: { positions_hash: positions_hash }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/portals/{portal.slug}/articles' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Lynomia owns the documentation; a tenant authors none of it, so every article verb is refused for an
  # administrator as much as for an agent (custom/app/policies/custom/article_policy.rb).
  describe 'tenant article authoring' do
    let(:base) { "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles" }
    let(:headers) { admin.create_new_auth_token }
    let!(:existing) { create(:article, account_id: account.id, portal: portal, author_id: admin.id) }

    context 'when listing articles' do
      let(:perform_request) { get base, headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when reading one article' do
      let(:perform_request) { get "#{base}/#{existing.id}", headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when creating an article' do
      let(:perform_request) do
        post base, params: { article: { title: 'new', content: 'body', author_id: admin.id } }, headers: headers,
                   as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when updating an article' do
      let(:perform_request) do
        put "#{base}/#{existing.id}", params: { article: { title: 'renamed' } }, headers: headers, as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when deleting an article' do
      let(:perform_request) { delete "#{base}/#{existing.id}", headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when reordering articles' do
      let(:perform_request) do
        post "#{base}/reorder", params: { positions: { existing.id => 1 } }, headers: headers, as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'
    end
  end
end
