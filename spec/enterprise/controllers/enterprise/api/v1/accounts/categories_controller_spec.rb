# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise Categories API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, name: 'test_portal', account_id: account.id, config: { allowed_locales: %w[en es] }) }
  let!(:category) { create(:category, name: 'category', portal: portal, account_id: account.id, slug: 'category_slug', position: 1) }

  # Create a custom role with knowledge_base_manage permission
  let!(:custom_role) { create(:custom_role, account: account, permissions: ['knowledge_base_manage']) }
  let!(:agent_with_role) { create(:user) }
  let(:agent_with_role_account_user) do
    create(:account_user, user: agent_with_role, account: account, role: :agent, custom_role: custom_role)
  end

  # Ensure the account_user with custom role is created before tests run
  before do
    agent_with_role_account_user
  end

  describe 'POST /api/v1/accounts/:account_id/portals/:portal_slug/categories/reorder' do
    context 'when it is an authenticated user' do
      it 'returns not found for invalid portal slug' do
        post "/api/v1/accounts/#{account.id}/portals/invalid-portal-slug/categories/reorder",
             params: { positions_hash: { category.id => 20 } },
             headers: agent_with_role.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # Enterprise grants these to a custom role holding knowledge_base_manage; Custom::CategoryPolicy refuses them.
  describe 'a custom role holding knowledge_base_manage' do
    let(:base) { "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories" }
    let(:headers) { agent_with_role.create_new_auth_token }

    it 'still cannot read or manage categories, which is where locales are managed' do
      [
        -> { get base, headers: headers, as: :json },
        -> { post base, params: { category: { name: 'n', slug: 's', locale: 'en' } }, headers: headers, as: :json },
        -> { put "#{base}/#{category.slug}", params: { category: { name: 'renamed' } }, headers: headers, as: :json },
        -> { delete "#{base}/#{category.slug}", headers: headers, as: :json },
        -> { post "#{base}/reorder", params: { positions: { category.id => 1 } }, headers: headers, as: :json }
      ].each do |request|
        request.call
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
