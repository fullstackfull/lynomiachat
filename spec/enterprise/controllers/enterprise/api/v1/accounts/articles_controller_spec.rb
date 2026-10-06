# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise Articles API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, name: 'test_portal', account_id: account.id) }
  let!(:category) { create(:category, name: 'category', portal: portal, account_id: account.id, locale: 'en', slug: 'category_slug') }
  let!(:article) { create(:article, category: category, portal: portal, account_id: account.id, author_id: admin.id) }

  # Create a custom role with knowledge_base_manage permission
  let!(:custom_role) { create(:custom_role, account: account, permissions: ['knowledge_base_manage']) }
  # Create user without account
  let!(:agent_with_role) { create(:user) }
  # Then create account_user association with custom_role
  let(:agent_with_role_account_user) do
    create(:account_user, user: agent_with_role, account: account, role: :agent, custom_role: custom_role)
  end

  # Ensure the account_user with custom role is created before tests run
  before do
    agent_with_role_account_user
  end

  # Enterprise::ArticlePolicy grants every article action to a custom role holding knowledge_base_manage.
  # Custom::ArticlePolicy prepends ahead of it and refuses, because Lynomia owns the documentation and no tenant role
  # authors it. These cases exist to pin that the grant is genuinely overridden at each endpoint.
  describe 'a custom role holding knowledge_base_manage' do
    let(:base) { "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles" }
    let(:headers) { agent_with_role.create_new_auth_token }

    it 'still cannot read, create, update, delete or reorder articles' do
      [
        -> { get base, headers: headers, as: :json },
        -> { get "#{base}/#{article.id}", headers: headers, as: :json },
        -> { post base, params: { article: { title: 't', content: 'c', author_id: admin.id } }, headers: headers, as: :json },
        -> { put "#{base}/#{article.id}", params: { article: { title: 'renamed' } }, headers: headers, as: :json },
        -> { delete "#{base}/#{article.id}", headers: headers, as: :json },
        -> { post "#{base}/reorder", params: { positions: { article.id => 1 } }, headers: headers, as: :json }
      ].each do |request|
        request.call
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it 'leaves the article untouched' do
      expect do
        delete "#{base}/#{article.id}", headers: headers, as: :json
      end.not_to(change { Article.exists?(article.id) })
    end
  end
end
