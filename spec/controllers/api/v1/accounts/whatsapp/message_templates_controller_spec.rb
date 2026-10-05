require 'rails_helper'

RSpec.describe 'WhatsApp message templates API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:templates_path) { "/api/v1/accounts/#{account.id}/whatsapp/message_templates" }
  let(:approved) do
    { 'id' => '100', 'name' => 'order_shipped', 'language' => 'en_US', 'category' => 'UTILITY', 'status' => 'APPROVED',
      'components' => [{ 'type' => 'BODY', 'text' => 'Shipped in {{1}} days' }], 'rejected_reason' => 'NONE' }
  end
  # The channel factory fixes the WABA itself: its before(:create) hook merges business_account_id over whatever a
  # test passes (spec/factories/channel/channel_whatsapp.rb:98-109).
  let(:waba_id) { '123456789' }
  let(:channel) do
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                              provider: 'whatsapp_cloud', message_templates: [approved])
  end

  describe 'GET /whatsapp/message_templates' do
    it 'lists what the account manages, with the inboxes that can send it and what may be done to it' do
      channel

      get templates_path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      template = response.parsed_body['payload'].sole
      expect(template).to include('name' => 'order_shipped', 'language' => 'en_US', 'state' => 'remote',
                                  'meta_status' => 'APPROVED', 'meta_template_id' => '100',
                                  'missing_at_meta' => false, 'rejected_reason' => 'NONE')
      expect(template['inboxes']).to eq([{ 'id' => channel.inbox.id, 'name' => channel.inbox.name }])
      expect(template['allowed_actions']).to contain_exactly('edit', 'delete', 'duplicate')
      expect(response.parsed_body['meta']['whatsapp_business_accounts'].sole['id']).to eq(waba_id)
    end

    it 'mirrors the channel snapshot on the first read, so nothing has to be migrated' do
      channel

      expect { get templates_path, headers: admin.create_new_auth_token, as: :json }
        .to change(Whatsapp::MessageTemplate, :count).by(1)
    end

    it 'shows a local draft as a draft, never as pending' do
      draft = Whatsapp::MessageTemplate.create!(account: account, business_account_id: waba_id, name: 'eid_offer',
                                                language: 'ar', category: 'MARKETING',
                                                components: [{ 'type' => 'BODY', 'text' => 'x' }])

      get templates_path, headers: admin.create_new_auth_token, as: :json

      template = response.parsed_body['payload'].find { |t| t['id'] == draft.id }
      expect(template).to include('state' => 'draft', 'meta_status' => nil, 'meta_template_id' => nil)
      expect(template['allowed_actions']).to contain_exactly('submit', 'edit', 'edit_category', 'delete', 'duplicate')
    end

    it 'offers no lifecycle action on a CSAT template, which has its own settings screen' do
      Whatsapp::MessageTemplate.create!(account: account, business_account_id: waba_id,
                                        name: "#{CsatTemplateNameService::CSAT_BASE_NAME}_7", language: 'en',
                                        category: 'UTILITY', meta_template_id: '55', meta_status: 'APPROVED')

      get templates_path, headers: admin.create_new_auth_token, as: :json

      csat = response.parsed_body['payload'].find { |t| t['name'].start_with?('customer_satisfaction_survey') }
      expect(csat['allowed_actions']).to eq(['duplicate'])
    end

    it 'never shows another account its templates' do
      other = create(:account)
      Whatsapp::MessageTemplate.create!(account: other, business_account_id: 'WABA_X', name: 'not_yours',
                                        language: 'en', category: 'UTILITY', meta_status: 'APPROVED')

      get templates_path, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to be_empty
    end

    it 'is for administrators only' do
      get templates_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'needs a login' do
      get templates_path, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /whatsapp/message_templates/:id' do
    it 'returns one template' do
      channel
      get templates_path, headers: admin.create_new_auth_token, as: :json
      id = response.parsed_body['payload'].sole['id']

      get "#{templates_path}/#{id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('id' => id, 'name' => 'order_shipped')
    end

    it 'cannot reach another account\'s template' do
      other = create(:account)
      theirs = Whatsapp::MessageTemplate.create!(account: other, business_account_id: 'WABA_X', name: 'not_yours',
                                                 language: 'en', category: 'UTILITY', meta_status: 'APPROVED')

      get "#{templates_path}/#{theirs.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
