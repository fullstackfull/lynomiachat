require 'rails_helper'

RSpec.describe 'Enterprise Onboarding API', type: :request do
  let(:account) { create(:account, domain: 'example.com') }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'PATCH /api/v1/accounts/{account.id}/onboarding' do
    context 'when finalizing account_details' do
      # Inbox/help-center setup is a cloud-only step; off cloud the flow finishes at account_details.
      before do
        account.update!(custom_attributes: { 'onboarding_step' => 'account_details' })
        allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
      end

      # Lynomia owns the documentation, so onboarding does not stand up a Help Center for the tenant
      # (custom/app/controllers/custom/api/v1/accounts/onboardings_controller.rb). This is the one tenant-authoring
      # path no policy could reach: HelpCenterCreationService is called internally during inbox setup, not through a
      # request anybody authorizes.
      it 'does not invoke HelpCenterCreationService, even when a website is present' do
        allow(Onboarding::HelpCenterCreationService).to receive(:new)

        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { website: 'acme.com', onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json

        expect(Onboarding::HelpCenterCreationService).not_to have_received(:new)
      end

      it 'creates no portal for the tenant' do
        expect do
          patch "/api/v1/accounts/#{account.id}/onboarding",
                params: { website: 'acme.com', onboarding_step: 'account_details' },
                headers: admin.create_new_auth_token, as: :json
        end.not_to(change { account.portals.count })
      end

      it 'still completes the onboarding step' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { website: 'acme.com', onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/onboarding/help_center_generation' do
    context 'when help center generation is in progress' do
      let(:generation_id) { 'generation-123' }
      let!(:portal) { create(:portal, account_id: account.id) }
      let!(:category) { create(:category, portal: portal, account_id: account.id) }

      before do
        account.update!(custom_attributes: { 'help_center_generation_id' => generation_id })
        create(:article, portal: portal, category: category, account_id: account.id, author_id: admin.id)
        Onboarding::HelpCenterGenerationState.start(generation_id, total: 3)
        Onboarding::HelpCenterGenerationState.record_article_finished(generation_id)
      end

      after do
        Redis::Alfred.delete(Onboarding::HelpCenterGenerationState.key(generation_id))
      end

      it 'returns Redis state and help center counts' do
        get "/api/v1/accounts/#{account.id}/onboarding/help_center_generation",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to include(
          'generation_id' => generation_id,
          'articles_count' => 1,
          'categories_count' => 1
        )
        expect(response.parsed_body['state']).to include(
          'status' => 'generating',
          'finished' => '1',
          'total' => '3'
        )
      end
    end
  end
end
