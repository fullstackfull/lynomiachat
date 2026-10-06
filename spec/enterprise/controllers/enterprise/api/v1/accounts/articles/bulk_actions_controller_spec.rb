require 'rails_helper'

RSpec.describe 'Article Bulk Actions API', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, name: 'test_portal', account: account, config: { allowed_locales: %w[en es fr] }) }
  let!(:category_en) { create(:category, portal: portal, account: account, locale: 'en', slug: 'getting-started') }
  let!(:category_es) { create(:category, portal: portal, account: account, locale: 'es', slug: 'primeros-pasos') }
  let!(:article_one) { create(:article, category: category_en, portal: portal, account: account, author_id: admin.id) }
  let!(:article_two) { create(:article, category: category_en, portal: portal, account: account, author_id: admin.id) }

  let(:translate_url) { "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/bulk_actions/translate" }

  describe 'POST articles/bulk_actions/translate' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post translate_url, params: { ids: [article_one.id], locale: 'es', category_id: category_es.id }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'returns unauthorized' do
        post translate_url,
             headers: agent.create_new_auth_token,
             params: { ids: [article_one.id], locale: 'es', category_id: category_es.id },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Bulk translation is authoring: it writes new articles in another locale. BulkActionsController authorizes through
  # authorize(Article, :create?), which Custom::ArticlePolicy refuses, so no tenant role reaches the Captain
  # translation jobs at all.
  describe 'tenant bulk translation' do
    let(:headers) { admin.create_new_auth_token }
    let(:perform_request) do
      post translate_url, params: { ids: [article_one.id, article_two.id], locale: 'es' }, headers: headers, as: :json
    end

    it_behaves_like 'a refused tenant Help Center request'

    it 'enqueues no translation job' do
      expect { perform_request }.not_to have_enqueued_job(Captain::Articles::TranslateJob)
    end
  end
end
