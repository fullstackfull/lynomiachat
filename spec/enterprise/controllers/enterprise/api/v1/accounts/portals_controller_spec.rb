# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enterprise Portal API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, name: 'test_portal', account_id: account.id) }

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

  describe 'POST /api/v1/accounts/:account_id/portals' do
    let(:portal_params) do
      {  portal: {
        name: 'test_portal',
        slug: 'test_kbase',
        custom_domain: 'https://support.chatwoot.dev'
      } }
    end

    context 'when it is an authenticated user' do
      it 'restricts portal creation for agents with knowledge_base_manage permission' do
        post "/api/v1/accounts/#{account.id}/portals",
             params: portal_params,
             headers: agent_with_role.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/portals/{portal.slug}/ssl_status' do
    let(:portal_with_domain) { create(:portal, slug: 'portal-with-domain', account_id: account.id, custom_domain: 'docs.example.com') }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/portals/#{portal_with_domain.slug}/ssl_status"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Enterprise::PortalPolicy grants update, edit and logo to a custom role holding knowledge_base_manage, and
  # ssl_status to any member. Custom::PortalPolicy refuses all of it.
  describe 'a custom role holding knowledge_base_manage' do
    let(:base) { "/api/v1/accounts/#{account.id}/portals" }
    let(:headers) { agent_with_role.create_new_auth_token }

    it 'still cannot read, update, configure or inspect a portal' do
      [
        -> { get base, headers: headers, as: :json },
        -> { get "#{base}/#{portal.slug}", headers: headers, as: :json },
        -> { put "#{base}/#{portal.slug}", params: { name: 'renamed' }, headers: headers, as: :json },
        -> { delete "#{base}/#{portal.slug}/logo", headers: headers, as: :json },
        -> { get "#{base}/#{portal.slug}/ssl_status", headers: headers, as: :json }
      ].each do |request|
        request.call
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
