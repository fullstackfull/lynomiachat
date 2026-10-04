require 'rails_helper'

RSpec.describe 'Contacts API', type: :request do
  let(:account) { create(:account) }
  let(:email_filter) do
    {
      attribute_key: 'email',
      filter_operator: 'contains',
      values: 'looped',
      query_operator: 'and',
      attribute_model: 'standard',
      custom_attribute_type: ''
    }
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let!(:contact) { create(:contact, :with_email, account: account, additional_attributes: { company_name: 'Company 1', country_code: 'IN' }) }
      let!(:contact_1) do
        create(:contact, :with_email, account: account, additional_attributes: { company_name: 'Test Company 1', country_code: 'CA' })
      end
      let(:contact_2) do
        create(:contact, :with_email, account: account, additional_attributes: { company_name: 'Marvel Company', country_code: 'AL' })
      end
      let(:contact_3) do
        create(:contact, :with_email, account: account, additional_attributes: { company_name: nil, country_code: nil })
      end
      let!(:contact_4) do
        create(:contact, :with_email, account: account, additional_attributes: { company_name: nil, country_code: nil })
      end
      let!(:contact_inbox) { create(:contact_inbox, contact: contact) }

      it 'returns all resolved contacts along with contact inboxes' do
        get "/api/v1/accounts/#{account.id}/contacts",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        response_body = response.parsed_body
        contact_emails = response_body['payload'].pluck('email')
        contact_inboxes_source_ids = response_body['payload'].flat_map { |c| c['contact_inboxes'].pluck('source_id') }

        expect(contact_emails).to include(contact.email)
        expect(contact_inboxes_source_ids).to include(contact_inbox.source_id)
      end

      it 'returns all contacts without contact inboxes' do
        get "/api/v1/accounts/#{account.id}/contacts?include_contact_inboxes=false",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body

        contact_emails = response_body['payload'].pluck('email')
        contact_inboxes = response_body['payload'].pluck('contact_inboxes').flatten.compact
        expect(contact_emails).to include(contact.email)
        expect(contact_inboxes).to eq([])
      end

      it 'returns limited information on inboxes' do
        get "/api/v1/accounts/#{account.id}/contacts?include_contact_inboxes=true",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body

        contact_emails = response_body['payload'].pluck('email')
        contact_inboxes = response_body['payload'].pluck('contact_inboxes').flatten.compact
        expect(contact_emails).to include(contact.email)
        first_inbox = contact_inboxes[0]['inbox']
        expect(first_inbox).to be_a(Hash)
        expect(first_inbox).to include('id', 'channel_id', 'channel_type', 'name', 'avatar_url', 'provider')

        expect(first_inbox).not_to include('imap_login',
                                           'imap_password',
                                           'imap_address',
                                           'imap_port',
                                           'imap_enabled',
                                           'imap_enable_ssl')

        expect(first_inbox).not_to include('smtp_login',
                                           'smtp_password',
                                           'smtp_address',
                                           'smtp_port',
                                           'smtp_enabled',
                                           'smtp_domain')

        expect(first_inbox).not_to include('hmac_token', 'provider_config')
      end

      it 'returns all contacts with company name desc order' do
        get "/api/v1/accounts/#{account.id}/contacts?include_contact_inboxes=false&sort=-company_name",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body
        expect(response_body['payload'].last['id']).to eq(contact_4.id)
        expect(response_body['payload'].last['email']).to eq(contact_4.email)
      end

      it 'returns all contacts with company name asc order with null values at last' do
        contact_3
        get "/api/v1/accounts/#{account.id}/contacts?include_contact_inboxes=false&sort=-company_name",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body
        expect(response_body['payload'].first(2).pluck('id')).to contain_exactly(contact.id, contact_1.id)
        expect(response_body['payload'].last(2).pluck('id')).to contain_exactly(contact_3.id, contact_4.id)
      end

      it 'returns all contacts with country name desc order with null values at last' do
        contact_from_albania = create(:contact, :with_email, account: account, additional_attributes: { country_code: 'AL', country: 'Albania' })
        get "/api/v1/accounts/#{account.id}/contacts?include_contact_inboxes=false&sort=country",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body
        expect(response_body['payload'].first['email']).to eq(contact_from_albania.email)
        expect(response_body['payload'].first['id']).to eq(contact_from_albania.id)
        expect(response_body['payload'].last['email']).to eq(contact_4.email)
      end

      it 'returns last seen at' do
        create(:conversation, contact: contact, account: account, inbox: contact_inbox.inbox, contact_last_seen_at: Time.now.utc)
        get "/api/v1/accounts/#{account.id}/contacts",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body
        expect(response_body['payload'].first['last_seen_at']).present?
      end

      it 'filters resolved contacts based on label filter' do
        contact_with_label1, contact_with_label2 = FactoryBot.create_list(:contact, 2, :with_email, account: account)
        contact_with_label1.update_labels(['label1'])
        contact_with_label2.update_labels(['label2'])

        get "/api/v1/accounts/#{account.id}/contacts",
            params: { labels: %w[label1 label2] },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body
        expect(response_body['meta']['count']).to eq(2)
        expect(response_body['payload'].pluck('email')).to include(contact_with_label1.email, contact_with_label2.email)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/contacts/import' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/contacts/import"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with out permission' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/contacts/import",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'creates a data import' do
        file = fixture_file_upload(Rails.root.join('spec/assets/contacts.csv'), 'text/csv')
        post "/api/v1/accounts/#{account.id}/contacts/import",
             headers: admin.create_new_auth_token,
             params: { import_file: file }

        expect(response).to have_http_status(:success)
        expect(account.data_imports.count).to eq(1)
        expect(account.data_imports.first.import_file.attached?).to be(true)
      end
    end

    context 'when file is empty' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'returns Unprocessable Entity' do
        post "/api/v1/accounts/#{account.id}/contacts/import",
             headers: admin.create_new_auth_token

        json_response = response.parsed_body

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['error']).to eq('File is blank')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/contacts/import, with the batch\'s own choices' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    def import(params)
      post "/api/v1/accounts/#{account.id}/contacts/import", headers: admin.create_new_auth_token, params: params
    end

    it 'turns pasted numbers into the file the importer already reads' do
      import({ phone_numbers: "+966551112233\n00966551112234, +966551112235" })

      expect(response).to have_http_status(:success)
      data_import = account.data_imports.last
      expect(data_import.import_file).to be_attached
      expect(data_import.import_file.download).to eq("phone_number\n+966551112233\n00966551112234\n+966551112235\n")
    end

    it 'keeps the batch\'s choices on the import itself, so the job reads them back' do
      create(:label, account: account, title: 'vip')
      import({ phone_numbers: '+966551112233', labels: ['VIP'], default_country: 'sa', duplicate_policy: 'keep' })

      expect(response).to have_http_status(:success)
      expect(account.data_imports.last.source_metadata).to eq(
        'labels' => ['vip'], 'default_country' => 'SA', 'duplicate_policy' => 'keep'
      )
    end

    it 'defaults to the policy this importer has always applied' do
      import({ phone_numbers: '+966551112233' })

      expect(account.data_imports.last.source_metadata['duplicate_policy']).to eq('update')
    end

    it 'refuses a label the account does not have, creating nothing' do
      import({ phone_numbers: '+966551112233', labels: ['ghost'] })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_types']['labels']).to eq(['not_in_account'])
      expect(account.data_imports.count).to eq(0)
    end

    it 'refuses a country that is not one' do
      import({ phone_numbers: '+966551112233', default_country: 'ZZ' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_types']['base']).to eq(['not_a_country'])
      expect(account.data_imports.count).to eq(0)
    end

    it 'refuses a duplicate policy that is not one of the two' do
      import({ phone_numbers: '+966551112233', duplicate_policy: 'merge' })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_types']['base']).to eq(['not_a_duplicate_policy'])
    end

    it 'refuses a file that is not a CSV' do
      import({ import_file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_types']['base']).to eq(['not_a_csv'])
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/contacts/import_preview' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    def preview(params)
      post "/api/v1/accounts/#{account.id}/contacts/import_preview", headers: admin.create_new_auth_token, params: params
      response.parsed_body
    end

    it 'returns unauthorized for an agent' do
      agent = create(:user, account: account, role: :agent)
      post "/api/v1/accounts/#{account.id}/contacts/import_preview",
           headers: agent.create_new_auth_token, params: { phone_numbers: '+966551112233' }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'classifies every row and creates nothing at all' do
      create(:contact, account: account, phone_number: '+966551112233')
      body = preview({ phone_numbers: "+966551112233\n+966551112234\n+966551112234\n0551112299" })

      expect(response).to have_http_status(:success)
      expect(body['total_rows']).to eq(4)
      expect(body['previewed_rows']).to eq(4)
      expect(body['counts']).to eq(
        'new_contact' => 1, 'update_existing' => 1, 'skip_existing' => 0,
        'duplicate_in_file' => 1, 'no_identity' => 0, 'invalid' => 1
      )
      expect(body['rows'].last).to include('classification' => 'invalid', 'reason' => 'phone_country_required')
      expect(account.data_imports.count).to eq(0)
      expect(account.contacts.count).to eq(1)
    end

    it 'shows what the batch\'s country would do to a local number, before it is applied' do
      body = preview({ phone_numbers: '0551112233', default_country: 'SA' })

      expect(body['default_country']).to eq('SA')
      expect(body['rows'].first).to include('classification' => 'new_contact', 'phone_number' => '0551112233',
                                            'normalized_phone_number' => '+966551112233')
    end

    it 'reports a contact in another account as new, never as existing' do
      create(:contact, account: create(:account), phone_number: '+966551112233')
      body = preview({ phone_numbers: '+966551112233' })

      expect(body['counts']).to include('new_contact' => 1, 'update_existing' => 0)
    end

    it 'counts the whole file even when it examines only the first rows' do
      stub_const('DataImport::ContactPreview::ROW_LIMIT', 2)
      body = preview({ phone_numbers: "+966551112233\n+966551112234\n+966551112235" })

      expect(body['total_rows']).to eq(3)
      expect(body['previewed_rows']).to eq(2)
      expect(body['row_limit']).to eq(2)
    end

    it 'reports a blank payload rather than an empty preview' do
      preview({})

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/contacts/export' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/contacts/export"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user with out permission' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/contacts/export",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'enqueues a contact export job' do
        expect(Account::ContactsExportJob).to receive(:perform_later).with(account.id, admin.id, nil, { :payload => nil, :label => nil }).once

        post "/api/v1/accounts/#{account.id}/contacts/export",
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
      end

      it 'enqueues a contact export job with sent_columns' do
        expect(Account::ContactsExportJob).to receive(:perform_later).with(account.id, admin.id, %w[phone_number email],
                                                                           { :payload => nil, :label => nil }).once

        post "/api/v1/accounts/#{account.id}/contacts/export",
             headers: admin.create_new_auth_token,
             params: { column_names: %w[phone_number email] }

        expect(response).to have_http_status(:success)
      end

      it 'enqueues a contact export job with payload' do
        expect(Account::ContactsExportJob).to receive(:perform_later).with(account.id, admin.id, nil,
                                                                           {
                                                                             :payload => [ActionController::Parameters.new(email_filter).permit!],
                                                                             :label => nil
                                                                           }).once

        post "/api/v1/accounts/#{account.id}/contacts/export",
             headers: admin.create_new_auth_token,
             params: { payload: [email_filter] }

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/active' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts/active"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let!(:contact) { create(:contact, account: account) }

      it 'returns no contacts if no are online' do
        get "/api/v1/accounts/#{account.id}/contacts/active",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include(contact.name)
      end

      it 'returns all contacts who are online' do
        allow(OnlineStatusTracker).to receive(:get_available_contact_ids).and_return([contact.id])

        get "/api/v1/accounts/#{account.id}/contacts/active",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(contact.name)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/search' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts/search"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let!(:contact1) { create(:contact, :with_email, account: account) }
      let!(:contact2) { create(:contact, :with_email, name: 'testcontact', account: account, email: 'test@test.com') }

      it 'returns all resolved contacts with contact inboxes' do
        get "/api/v1/accounts/#{account.id}/contacts/search",
            params: { q: contact2.email },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(response.body).to include(contact2.email)
        expect(response.body).not_to include(contact1.email)
      end

      it 'matches the contact ignoring the case in email' do
        get "/api/v1/accounts/#{account.id}/contacts/search",
            params: { q: 'Test@Test.com' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(contact2.email)
        expect(response.body).not_to include(contact1.email)
      end

      it 'matches the contact ignoring the case in name' do
        get "/api/v1/accounts/#{account.id}/contacts/search",
            params: { q: 'TestContact' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(contact2.email)
        expect(response.body).not_to include(contact1.email)
      end

      it 'matches the resolved contact respecting the identifier character casing' do
        contact_normal = create(:contact, name: 'testcontact', account: account, identifier: 'testidentifer')
        contact_special = create(:contact, name: 'testcontact', account: account, identifier: 'TestIdentifier')
        get "/api/v1/accounts/#{account.id}/contacts/search",
            params: { q: 'TestIdentifier' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(contact_special.identifier)
        expect(response.body).not_to include(contact_normal.identifier)
      end

      it 'returns has_more as false when results fit in one page' do
        get "/api/v1/accounts/#{account.id}/contacts/search",
            params: { q: contact2.email },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body
        expect(response_body['meta']['has_more']).to be(false)
        expect(response_body['meta']['count']).to eq(1)
      end

      it 'returns has_more as true when there are more results' do
        # Create 16 contacts (more than RESULTS_PER_PAGE which is 15)
        create_list(:contact, 16, account: account, name: 'searchable_contact')

        get "/api/v1/accounts/#{account.id}/contacts/search",
            params: { q: 'searchable_contact' },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body
        expect(response_body['meta']['has_more']).to be(true)
        expect(response_body['meta']['count']).to eq(15)
        expect(response_body['payload'].length).to eq(15)
      end

      it 'returns has_more as false on the last page' do
        # Create 16 contacts
        create_list(:contact, 16, account: account, name: 'searchable_contact')

        get "/api/v1/accounts/#{account.id}/contacts/search",
            params: { q: 'searchable_contact', page: 2 },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body
        expect(response_body['meta']['has_more']).to be(false)
        expect(response_body['meta']['count']).to eq(1)
        expect(response_body['payload'].length).to eq(1)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/filter' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts/filter"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let!(:contact1) { create(:contact, :with_email, account: account, additional_attributes: { country_code: 'US' }) }
      let!(:contact2) do
        create(:contact, :with_email, name: 'testcontact', account: account, email: 'test@test.com', additional_attributes: { country_code: 'US' })
      end

      it 'returns all contacts when query is empty' do
        post "/api/v1/accounts/#{account.id}/contacts/filter",
             params: { payload: [
               attribute_key: 'country_code',
               filter_operator: 'equal_to',
               values: ['US']
             ] },
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(response.body).to include(contact2.email)
        expect(response.body).to include(contact1.email)
      end

      it 'returns error the query operator is invalid' do
        post "/api/v1/accounts/#{account.id}/contacts/filter",
             params: { payload: [
               attribute_key: 'country_code',
               filter_operator: 'eq',
               values: ['US']
             ] },
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Invalid operator. The allowed operators for country_code are [equal_to,not_equal_to]')
      end

      it 'returns error the query value is invalid' do
        post "/api/v1/accounts/#{account.id}/contacts/filter",
             params: { payload: [
               attribute_key: 'country_code',
               filter_operator: 'equal_to',
               values: []
             ] },
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Invalid value. The values provided for country_code are invalid"')
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/:id' do
    let!(:contact) { create(:contact, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'shows the contact' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(response.body).to include(contact.name)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/contacts/:id/contactable_inboxes' do
    let!(:contact) { create(:contact, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/contactable_inboxes"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let!(:twilio_sms) { create(:channel_twilio_sms, account: account) }
      let!(:twilio_sms_inbox) { create(:inbox, channel: twilio_sms, account: account) }
      let!(:twilio_whatsapp) { create(:channel_twilio_sms, medium: :whatsapp, account: account) }
      let!(:twilio_whatsapp_inbox) { create(:inbox, channel: twilio_whatsapp, account: account) }

      it 'shows the contactable inboxes which the user has access to' do
        create(:inbox_member, user: agent, inbox: twilio_whatsapp_inbox)

        inbox_service = double
        allow(Contacts::ContactableInboxesService).to receive(:new).and_return(inbox_service)
        allow(inbox_service).to receive(:get).and_return([
                                                           { source_id: '1123', inbox: twilio_sms_inbox },
                                                           { source_id: '1123', inbox: twilio_whatsapp_inbox }
                                                         ])
        expect(inbox_service).to receive(:get)
        get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/contactable_inboxes",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        # only the inboxes which agent has access to are shown
        expect(response.parsed_body['payload'].pluck('inbox').pluck('id')).to eq([twilio_whatsapp_inbox.id])
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/contacts' do
    let(:custom_attributes) { { test: 'test', test1: 'test1' } }
    let(:valid_params) { { name: 'test', custom_attributes: custom_attributes } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        expect { post "/api/v1/accounts/#{account.id}/contacts", params: valid_params }.not_to change(Contact, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let(:inbox) { create(:inbox, account: account) }

      it 'creates the contact' do
        expect do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params
        end.to change(Contact, :count).by(1)

        expect(response).to have_http_status(:success)

        # custom attributes are updated
        json_response = response.parsed_body
        expect(json_response['payload']['contact']['custom_attributes']).to eq({ 'test' => 'test', 'test1' => 'test1' })
      end

      it 'does not create the contact' do
        valid_params[:name] = 'test' * 999

        post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                        params: valid_params

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = response.parsed_body
        expect(json_response['message']).to eq('Name is too long (maximum is 255 characters)')
      end

      context 'when the request carries labels' do
        let!(:label) { create(:label, account: account, title: 'vip') }

        it 'persists the label, returns it, and makes the contact findable by it' do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(labels: [label.title])

          expect(response).to have_http_status(:success)

          contact = Contact.last
          expect(contact.label_list).to contain_exactly('vip')
          expect(response.parsed_body['payload']['contact']['labels']).to eq(['vip'])
          expect(account.contacts.tagged_with('vip', any: true)).to include(contact)
        end

        # The reported workflow, end to end over HTTP: create on the label page, then read the label page back.
        it 'is returned by the label-filtered list the contact was created from' do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(phone_number: '+96522201234',
                                                                                     labels: [label.title])
          expect(response).to have_http_status(:success)
          created_id = response.parsed_body['payload']['contact']['id']

          get "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                         params: { labels: [label.title] }

          expect(response).to have_http_status(:success)
          expect(response.parsed_body['payload'].pluck('id')).to include(created_id)
        end

        it 'is not returned by a different label\'s list' do
          other = create(:label, account: account, title: 'cold')
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(phone_number: '+96522201235',
                                                                                     labels: [label.title])
          created_id = response.parsed_body['payload']['contact']['id']

          get "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                         params: { labels: [other.title] }

          expect(response.parsed_body['payload'].pluck('id')).not_to include(created_id)
        end

        it 'writes a Contact tagging, not a Conversation one' do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(labels: [label.title])

          tagging = ActsAsTaggableOn::Tagging.find_by(taggable_type: 'Contact', taggable_id: Contact.last.id)
          expect(tagging.context).to eq('labels')
          expect(tagging.tag.name).to eq('vip')
        end

        it 'accepts the catalogue label whatever case the client sends' do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(labels: ['  VIP '])

          expect(response).to have_http_status(:success)
          expect(Contact.last.label_list).to contain_exactly('vip')
          expect(ActsAsTaggableOn::Tag.where(name: 'vip').count).to eq(1)
        end

        it 'rejects a label that is not in the account catalogue, and creates nothing' do
          expect do
            post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                            params: valid_params.merge(labels: ['not-a-label'])
          end.not_to change(Contact, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['attributes']).to include('labels')
          expect(response.parsed_body['errors']['labels'].first).to include('not-a-label')
          expect(response.parsed_body['error_types']['labels']).to eq(['not_in_account'])
        end

        it 'rejects another account\'s label without revealing that it exists' do
          other_label = create(:label, account: create(:account), title: 'their-label')

          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(labels: [other_label.title])

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['errors']['labels'].first)
            .to eq('Labels do not exist in this account: their-label')
        end

        it 'does not apply a label when the contact itself is invalid' do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(phone_number: '0551112233',
                                                                                     labels: [label.title])

          expect(response).to have_http_status(:unprocessable_entity)
          expect(account.contacts.tagged_with('vip', any: true)).to be_empty
        end

        # One save, so one event: the label is part of the contact's creation rather than an update that
        # immediately follows it.
        it 'dispatches contact.created once and no contact.updated' do
          allow(Rails.configuration.dispatcher).to receive(:dispatch)

          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(labels: [label.title])

          expect(Rails.configuration.dispatcher).to have_received(:dispatch)
            .with('contact.created', anything, hash_including(:contact)).once
          expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
            .with('contact.updated', any_args)
        end

        it 'leaves the contact unlabelled when no labels are sent' do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params

          expect(response).to have_http_status(:success)
          expect(Contact.last.label_list).to be_empty
          expect(response.parsed_body['payload']['contact']['labels']).to eq([])
        end
      end

      context 'when the phone number is not in e164 format' do
        it 'returns a structured 422 naming the phone number' do
          expect do
            post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                            params: valid_params.merge(phone_number: '0551112233')
          end.not_to change(Contact, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['attributes']).to include('phone_number')
          expect(response.parsed_body['errors']['phone_number'])
            .to eq(['Phone number should be in e164 format'])
          expect(response.parsed_body['error_types']['phone_number']).to eq(['invalid'])
          expect(response.parsed_body['message']).to eq('Phone number should be in e164 format')
        end

        # The validation is structural, not a real-number check: a dial code concatenated onto a
        # trunk-prefixed local number is usually short enough to pass it, so the old input behaviour stored a
        # wrong number silently rather than being rejected. This is why B4 normalizes before submitting.
        it 'accepts a dial code concatenated onto a trunk prefix, because the rule is only structural' do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(phone_number: '+9650551112233')

          expect(response).to have_http_status(:success)
          expect(Contact.last.phone_number).to eq('+9650551112233')
        end

        it 'rejects it once the concatenation exceeds fifteen digits' do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(phone_number: '+9650123456789012')

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['errors']['phone_number'])
            .to eq(['Phone number should be in e164 format'])
        end
      end

      context 'when the phone number already belongs to a contact in this account' do
        let!(:existing) { create(:contact, account: account, phone_number: '+96522201234') }

        it 'returns a structured 422 the client can tell apart from a format error' do
          expect do
            post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                            params: valid_params.merge(phone_number: existing.phone_number)
          end.not_to change(Contact, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['attributes']).to include('phone_number')
          expect(response.parsed_body['errors']['phone_number'])
            .to eq(['Phone number has already been taken'])
          # The type is what lets the client tell this apart from a format rejection on the same field.
          expect(response.parsed_body['error_types']['phone_number']).to eq(['taken'])
        end

        it 'does not name or identify the existing contact in the response' do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge(phone_number: existing.phone_number)

          expect(response.body).not_to include(existing.name)
          expect(response.body).not_to include(existing.id.to_s)
        end
      end

      context 'when the phone number belongs to a contact in another account' do
        it 'creates the contact and discloses nothing about the other account' do
          other_contact = create(:contact, account: create(:account), phone_number: '+96522209999')

          expect do
            post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                            params: valid_params.merge(phone_number: other_contact.phone_number)
          end.to change(Contact, :count).by(1)

          expect(response).to have_http_status(:success)
          expect(response.body).not_to include(other_contact.name)
        end
      end

      it 'creates the contact inbox when inbox id is passed' do
        expect do
          post "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token,
                                                          params: valid_params.merge({ inbox_id: inbox.id })
        end.to change(ContactInbox, :count).by(1)

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/contacts/:id' do
    let(:custom_attributes) { { test: 'test', test1: 'test1' } }
    let(:additional_attributes) { { attr1: 'attr1', attr2: 'attr2' } }
    let!(:contact) { create(:contact, account: account, custom_attributes: custom_attributes, additional_attributes: additional_attributes) }
    let(:valid_params) do
      { name: 'Test Blub', custom_attributes: { test: 'new test', test2: 'test2' }, additional_attributes: { attr2: 'new attr2', attr3: 'attr3' } }
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
            params: valid_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'updates the contact' do
        patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
              headers: admin.create_new_auth_token,
              params: valid_params,
              as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(contact.reload.name).to eq('Test Blub')
        # custom attributes are merged properly without overwriting existing ones
        expect(contact.custom_attributes).to eq({ 'test' => 'new test', 'test1' => 'test1', 'test2' => 'test2' })
        expect(contact.additional_attributes).to eq({ 'attr1' => 'attr1', 'attr2' => 'new attr2', 'attr3' => 'attr3' })
      end

      it 'prevents the update of contact of another account' do
        other_account = create(:account)
        other_contact = create(:contact, account: other_account)

        patch "/api/v1/accounts/#{account.id}/contacts/#{other_contact.id}",
              headers: admin.create_new_auth_token,
              params: valid_params,
              as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'prevents updating with an existing email' do
        other_contact = create(:contact, account: account, email: 'test1@example.com')

        patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
              headers: admin.create_new_auth_token,
              params: valid_params.merge({ email: other_contact.email }),
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['attributes']).to include('email')
      end

      it 'prevents updating with an existing phone number' do
        other_contact = create(:contact, account: account, phone_number: '+12000000')

        patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
              headers: admin.create_new_auth_token,
              params: valid_params.merge({ phone_number: other_contact.phone_number }),
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['attributes']).to include('phone_number')
      end

      it 'updates avatar' do
        # no avatar before upload
        expect(contact.avatar.attached?).to be(false)
        file = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
        patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
              params: valid_params.merge(avatar: file),
              headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        contact.reload
        expect(contact.avatar.attached?).to be(true)
      end

      it 'updated avatar with avatar_url' do
        patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
              params: valid_params.merge(avatar_url: 'http://example.com/avatar.png'),
              headers: admin.create_new_auth_token
        expect(response).to have_http_status(:success)
        expect(Avatar::AvatarFromUrlJob).to have_been_enqueued.with(contact, 'http://example.com/avatar.png')
      end

      it 'allows blocking of contact' do
        patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
              params: { blocked: true },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(contact.reload.blocked).to be(true)
      end

      it 'allows unblocking of contact' do
        contact.update(blocked: true)
        patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
              params: { blocked: false },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(contact.reload.blocked).to be(false)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/contacts/:id', :contact_delete do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'deletes the contact for administrator user' do
        allow(OnlineStatusTracker).to receive(:get_presence).and_return(false)
        delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
               headers: admin.create_new_auth_token

        expect(contact.conversations).to be_empty
        expect(contact.inboxes).to be_empty
        expect(contact.contact_inboxes).to be_empty
        expect(contact.csat_survey_responses).to be_empty
        expect { contact.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(response).to have_http_status(:success)
      end

      it 'does not delete the contact if online' do
        allow(OnlineStatusTracker).to receive(:get_presence).and_return(true)

        delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
               headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns unauthorized for agent user' do
        delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
               headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/contacts/:id/destroy_custom_attributes' do
    let(:custom_attributes) { { test: 'test', test1: 'test1' } }
    let!(:contact) { create(:contact, account: account, custom_attributes: custom_attributes) }
    let(:valid_params) { { custom_attributes: ['test'] } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/destroy_custom_attributes",
             params: valid_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'delete the custom attribute' do
        post "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/destroy_custom_attributes",
             headers: admin.create_new_auth_token,
             params: valid_params,
             as: :json

        expect(response).to have_http_status(:success)
        expect(contact.reload.custom_attributes).to eq({ 'test1' => 'test1' })
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/contacts/:id/avatar' do
    let(:contact) { create(:contact, account: account) }
    let(:agent) { create(:user, account: account, role: :agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/avatar"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      before do
        create(:contact, account: account)
        contact.avatar.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      end

      it 'delete contact avatar' do
        delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/avatar",
               headers: agent.create_new_auth_token,
               as: :json

        expect { contact.avatar.attachment.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect(response).to have_http_status(:success)
      end
    end
  end
end
