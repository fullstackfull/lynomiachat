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
  # test passes (spec/factories/channel/channel_whatsapp.rb:98-109), so a second WABA is set after the fact.
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

  describe 'POST /whatsapp/message_templates' do
    let(:draft) do
      { inbox_id: channel.inbox.id, name: 'eid_offer', language: 'ar', category: 'MARKETING',
        parameter_format: 'POSITIONAL',
        components: [{ type: 'BODY', text: 'Hello {{1}}, your order is ready',
                       example: { body_text: [['Dana']] } }] }
    end

    it 'creates a local draft Meta has never seen' do
      post templates_path, headers: admin.create_new_auth_token, as: :json, params: draft

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('name' => 'eid_offer', 'state' => 'draft', 'meta_status' => nil,
                                              'validation_problems' => [])
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
      expect(Whatsapp::MessageTemplate.sole.business_account_id).to eq(waba_id)
    end

    it 'keeps only the keys Meta documents' do
      post templates_path, headers: admin.create_new_auth_token, as: :json,
                           params: draft.deep_merge(components: [draft[:components].first.merge(smuggled: 'x')])

      expect(response).to have_http_status(:created)
      expect(Whatsapp::MessageTemplate.sole.components.sole.keys).to contain_exactly('type', 'text', 'example')
    end

    # A name Meta can never accept is identity, so it is refused at the boundary with a field error a form can place.
    it 'refuses a name WhatsApp would not accept' do
      post templates_path, headers: admin.create_new_auth_token, as: :json, params: draft.merge(name: 'Eid Offer')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to include('name')
      expect(Whatsapp::MessageTemplate.count).to be_zero
    end

    # Everything Meta's content rules cover is reported per field instead, so a draft can be saved and fixed rather
    # than losing the work -- and a submit refuses on the same list.
    it 'reports what Meta would reject, by field, instead of letting a review cycle find it' do
      post templates_path, headers: admin.create_new_auth_token, as: :json,
                           params: draft.merge(components: [{ type: 'BODY', text: '{{1}} your order' },
                                                            { type: 'FOOTER', text: 'from {{2}}' },
                                                            { type: 'BUTTONS',
                                                              buttons: [{ type: 'QUICK_REPLY', text: 'Yes' },
                                                                        { type: 'URL', text: 'Track',
                                                                          url: 'https://x.test/{{1}}/more' },
                                                                        { type: 'QUICK_REPLY', text: 'No' }] }])

      expect(response).to have_http_status(:created)
      problems = response.parsed_body['validation_problems']
      expect(problems).to include({ 'field' => 'body', 'code' => 'variable_at_edge' },
                                  { 'field' => 'body', 'code' => 'variable_example_missing' },
                                  { 'field' => 'footer', 'code' => 'footer_has_variables' },
                                  { 'field' => 'buttons', 'code' => 'buttons_quick_reply_not_grouped' },
                                  { 'field' => 'buttons.1', 'code' => 'button_url_variable_not_at_end' },
                                  { 'field' => 'buttons.1', 'code' => 'button_example_missing' })
    end

    it 'is for administrators only' do
      post templates_path, headers: agent.create_new_auth_token, as: :json, params: draft

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /whatsapp/message_templates/:id/submit' do
    # This group builds its own rows, so the channel carries no snapshot: a mirror pass would reconcile the snapshot
    # over them on the first read of the request.
    let(:channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                                provider: 'whatsapp_cloud', message_templates: [])
    end
    let(:create_url) { "https://graph.facebook.com/v24.0/#{waba_id}/message_templates" }
    let!(:template) do
      channel
      Whatsapp::MessageTemplate.create!(account: account, business_account_id: waba_id, name: 'eid_offer',
                                        language: 'ar', category: 'MARKETING',
                                        components: [{ 'type' => 'BODY', 'text' => 'Hello {{1}}, your order is ready',
                                                       'example' => { 'body_text' => [['Dana']] } }])
    end

    it 'hands the draft to Meta and records what Meta said' do
      stub_request(:post, create_url)
        .to_return(status: 200, body: { id: '9981', status: 'PENDING', category: 'UTILITY' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      post "#{templates_path}/#{template.id}/submit", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('state' => 'remote', 'meta_status' => 'PENDING',
                                              'meta_template_id' => '9981')
      # The category comes from Meta's response, which can differ from the one submitted.
      expect(template.reload.category).to eq('UTILITY')
      expect(a_request(:post, create_url)
        .with(headers: { 'Authorization' => 'Bearer test_key' },
              body: hash_including('name' => 'eid_offer', 'language' => 'ar', 'category' => 'MARKETING')))
        .to have_been_made.once
    end

    it 'does not create two templates at Meta when Submit is clicked twice' do
      stub_request(:post, create_url)
        .to_return(status: 200, body: { id: '9981', status: 'PENDING' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      2.times { post "#{templates_path}/#{template.id}/submit", headers: admin.create_new_auth_token, as: :json }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']['code']).to eq('ALREADY_AT_META')
      expect(a_request(:post, create_url)).to have_been_made.once
    end

    it 'keeps the draft and says why when Meta refuses the call' do
      stub_request(:post, create_url)
        .to_return(status: 400,
                   body: { error: { message: 'Content in This Language Already Exists', code: 100,
                                    error_subcode: 2_388_024, fbtrace_id: 'A1' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      post "#{templates_path}/#{template.id}/submit", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']['code']).to eq('NAME_TAKEN')
      template.reload
      expect(template.components).to be_present
      expect(template.local_state).to eq(:draft)
      expect(template.submission_error).to include('NAME_TAKEN')
    end

    it 'refuses to submit a draft Meta would reject, without calling Meta' do
      # update_columns: this is a state Meta produced, not one a client could post.
      template.update_columns(components: [{ 'type' => 'BODY', 'text' => '{{1}} is ready' }]) # rubocop:disable Rails/SkipsModelValidations

      post "#{templates_path}/#{template.id}/submit", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']['code']).to eq('INVALID_TEMPLATE')
      expect(response.parsed_body['error']['details']).to include({ 'field' => 'body', 'code' => 'variable_at_edge' })
      expect(a_request(:post, create_url)).not_to have_been_made
    end
  end

  describe 'PATCH /whatsapp/message_templates/:id' do
    # This group builds its own rows, so the channel carries no snapshot: a mirror pass would reconcile the snapshot
    # over them on the first read of the request.
    let(:channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                                provider: 'whatsapp_cloud', message_templates: [])
    end
    let!(:template) do
      channel
      Whatsapp::MessageTemplate.create!(account: account, business_account_id: waba_id, name: 'order_shipped',
                                        language: 'en_US', category: 'UTILITY', meta_template_id: '100',
                                        meta_status: 'APPROVED',
                                        components: [{ 'type' => 'BODY', 'text' => 'Your order is on its way' }])
    end
    let(:edit_url) { 'https://graph.facebook.com/v24.0/100' }

    it 'sends the complete component set, because Meta replaces all of them' do
      stub_request(:post, edit_url).to_return(status: 200, body: { success: true }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })

      patch "#{templates_path}/#{template.id}", headers: admin.create_new_auth_token, as: :json,
                                                params: { components: [{ type: 'BODY', text: 'On its way today' },
                                                                       { type: 'FOOTER', text: 'Lynomia' }] }

      expect(response).to have_http_status(:success)
      expect(a_request(:post, edit_url)
        .with(body: hash_including('components' => [{ 'type' => 'BODY', 'text' => 'On its way today' },
                                                    { 'type' => 'FOOTER', 'text' => 'Lynomia' }])))
        .to have_been_made.once
      # Meta re-reviews an edited template and its response says nothing about status, so nothing claims approval.
      expect(template.reload.meta_status).to eq('PENDING')
    end

    it 'refuses to change the category of an approved template, as Meta does' do
      patch "#{templates_path}/#{template.id}", headers: admin.create_new_auth_token, as: :json,
                                                params: { category: 'MARKETING' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']['code']).to eq('CATEGORY_NOT_EDITABLE')
      expect(a_request(:post, edit_url)).not_to have_been_made
    end

    it 'refuses to edit a template Meta has in review' do
      template.update_columns(meta_status: 'PENDING') # rubocop:disable Rails/SkipsModelValidations

      patch "#{templates_path}/#{template.id}", headers: admin.create_new_auth_token, as: :json,
                                                params: { components: [{ type: 'BODY', text: 'x' }] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']['code']).to eq('NOT_EDITABLE')
    end

    it 'changes a draft without calling Meta at all' do
      draft = Whatsapp::MessageTemplate.create!(account: account, business_account_id: waba_id, name: 'eid_offer',
                                                language: 'ar', category: 'MARKETING',
                                                components: [{ 'type' => 'BODY', 'text' => 'x' }])

      patch "#{templates_path}/#{draft.id}", headers: admin.create_new_auth_token, as: :json,
                                             params: { category: 'UTILITY',
                                                       components: [{ type: 'BODY', text: 'Your order is ready' }] }

      expect(response).to have_http_status(:success)
      expect(draft.reload.category).to eq('UTILITY')
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end

  describe 'DELETE /whatsapp/message_templates/:id' do
    # This group builds its own rows, so the channel carries no snapshot: a mirror pass would reconcile the snapshot
    # over them on the first read of the request.
    let(:channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                                provider: 'whatsapp_cloud', message_templates: [])
    end
    let!(:template) do
      channel
      Whatsapp::MessageTemplate.create!(account: account, business_account_id: waba_id, name: 'order_shipped',
                                        language: 'en_US', category: 'UTILITY', meta_template_id: '100',
                                        meta_status: 'APPROVED')
    end

    it 'deletes by id with the name, never by name alone' do
      stub_request(:delete, "https://graph.facebook.com/v24.0/#{waba_id}/message_templates")
        .with(query: { name: 'order_shipped', hsm_id: '100' })
        .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      delete "#{templates_path}/#{template.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(Whatsapp::MessageTemplate.where(id: template.id)).to be_empty
    end

    it 'refuses to delete a template Meta has disabled, as Meta does' do
      template.update_columns(meta_status: 'DISABLED') # rubocop:disable Rails/SkipsModelValidations

      delete "#{templates_path}/#{template.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']['code']).to eq('NOT_DELETABLE')
      expect(a_request(:delete, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'deletes a draft with no Meta call at all' do
      draft = Whatsapp::MessageTemplate.create!(account: account, business_account_id: waba_id, name: 'eid_offer',
                                                language: 'ar', category: 'MARKETING')

      delete "#{templates_path}/#{draft.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end

  describe 'POST /whatsapp/message_templates/:id/duplicate' do
    # This group builds its own rows, so the channel carries no snapshot: a mirror pass would reconcile the snapshot
    # over them on the first read of the request.
    let(:channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                                provider: 'whatsapp_cloud', message_templates: [])
    end
    let!(:template) do
      channel
      Whatsapp::MessageTemplate.create!(account: account, business_account_id: waba_id, name: 'order_shipped',
                                        language: 'en_US', category: 'UTILITY', meta_template_id: '100',
                                        meta_status: 'APPROVED', meta_payload: { 'rejected_reason' => 'NONE' },
                                        components: [{ 'type' => 'BODY', 'text' => 'On its way' }])
    end

    it 'copies the content into a new local draft and nothing of Meta\'s' do
      post "#{templates_path}/#{template.id}/duplicate", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('name' => 'order_shipped_copy', 'state' => 'draft',
                                              'meta_template_id' => nil, 'meta_status' => nil,
                                              'rejected_reason' => nil)
      expect(response.parsed_body['components']).to eq([{ 'type' => 'BODY', 'text' => 'On its way' }])
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'never reuses a name, because Meta blocks a deleted one for thirty days' do
      post "#{templates_path}/#{template.id}/duplicate", headers: admin.create_new_auth_token, as: :json
      post "#{templates_path}/#{template.id}/duplicate", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['name']).to eq('order_shipped_copy_2')
    end
  end

  # One account, two WhatsApp Business Accounts: a template belongs to a WABA, and several inboxes can share one, so
  # neither may be allowed to stand for the other (docs/whatsapp-template-manager/04-permissions-and-tenancy.md).
  describe 'with more than one WhatsApp Business Account' do
    let(:second_waba) { 'WABA_SECOND' }
    let!(:second_channel) do
      channel
      other = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false,
                                        provider: 'whatsapp_cloud',
                                        message_templates: [approved.merge('id' => '200')])
      other.update!(provider_config: other.provider_config.merge('business_account_id' => second_waba))
      other
    end

    it 'keeps the same template name on each account as its own template' do
      get templates_path, headers: admin.create_new_auth_token, as: :json

      shipped = response.parsed_body['payload'].select { |t| t['name'] == 'order_shipped' }
      expect(shipped.map { |t| t['business_account_id'] }).to contain_exactly(waba_id, second_waba)
      expect(shipped.map { |t| t['meta_template_id'] }).to contain_exactly('100', '200')
    end

    it 'tells each one which inboxes can send it' do
      get templates_path, headers: admin.create_new_auth_token, as: :json

      by_waba = response.parsed_body['payload'].index_by { |t| t['business_account_id'] }
      expect(by_waba[waba_id]['inboxes'].pluck('id')).to eq([channel.inbox.id])
      expect(by_waba[second_waba]['inboxes'].pluck('id')).to eq([second_channel.inbox.id])
    end

    it 'reports both business accounts, each with when it was last read' do
      get templates_path, headers: admin.create_new_auth_token, as: :json

      wabas = response.parsed_body['meta']['whatsapp_business_accounts']
      expect(wabas.pluck('id')).to contain_exactly(waba_id, second_waba)
      expect(wabas.map { |waba| waba['last_synced_at'] }).to all(be_present)
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
