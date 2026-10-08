require 'rails_helper'

RSpec.describe 'Article Bulk Actions API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, name: 'test_portal', account: account, config: { allowed_locales: %w[en es] }) }
  let!(:category) { create(:category, portal: portal, account: account, locale: 'en', slug: 'getting-started') }
  let!(:article_one) { create(:article, category: category, portal: portal, account: account, author: admin, status: :draft) }
  let!(:article_two) { create(:article, category: category, portal: portal, account: account, author: admin, status: :draft) }
  let!(:article_three) { create(:article, category: category, portal: portal, account: account, author: admin, status: :published) }

  let(:base_url) { "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/bulk_actions" }

  describe 'PATCH articles/bulk_actions/update_status' do
    let(:update_status_url) { "#{base_url}/update_status" }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch update_status_url, params: { ids: [article_one.id], status: 'published' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'returns unauthorized' do
        patch update_status_url,
              headers: agent.create_new_auth_token,
              params: { ids: [article_one.id], status: 'published' },
              as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE articles/bulk_actions/delete_articles' do
    let(:destroy_url) { "#{base_url}/delete_articles" }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete destroy_url, params: { ids: [article_one.id] }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'returns unauthorized' do
        delete destroy_url,
               headers: agent.create_new_auth_token,
               params: { ids: [article_one.id] },
               as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Publishing is authoring: Articles::BulkActionsController authorizes through authorize(Article, :create?), so the
  # article policy denial closes every bulk verb at once (custom/app/policies/custom/article_policy.rb).
  describe 'tenant bulk article authoring' do
    let(:headers) { admin.create_new_auth_token }
    let(:ids) { [article_one.id, article_two.id] }

    context 'when publishing articles in bulk' do
      let(:perform_request) do
        patch "#{base_url}/update_status", params: { ids: ids, status: 'published' }, headers: headers, as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'

      it 'leaves the articles as they were, inside the id list and outside it' do
        perform_request

        expect(article_one.reload.status).to eq('draft')
        expect(article_two.reload.status).to eq('draft')
        expect(article_three.reload.status).to eq('published')
      end
    end

    context 'when moving articles to another category in bulk' do
      let(:perform_request) do
        patch "#{base_url}/update_category", params: { ids: ids, category_id: category.id }, headers: headers,
                                             as: :json
      end

      it_behaves_like 'a refused tenant Help Center request'
    end

    context 'when deleting articles in bulk' do
      let(:perform_request) { delete "#{base_url}/delete_articles", params: { ids: ids }, headers: headers, as: :json }

      it_behaves_like 'a refused tenant Help Center request'

      it 'deletes nothing' do
        expect { perform_request }.not_to(change { Article.where(id: ids).count })
      end
    end
  end
end
