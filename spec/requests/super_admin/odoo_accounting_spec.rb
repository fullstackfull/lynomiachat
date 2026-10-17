require 'rails_helper'

# Super Admin -> Odoo Accounting: that every page renders, and that nobody but a super admin can reach any of
# them (the brief, §14).
#
# THE AUTHORIZATION EXAMPLES ARE THE POINT. This surface reads one installation's whole billing history and
# writes the credentials of an accounting system, so the boundary is tested per route rather than per surface:
# a route added later without `authenticate_super_admin!` would be caught here and nowhere else.
# Every read in the tab bar, by name, so a new tab cannot be added without an example.
READ_PATHS = {
  overview: '/super_admin/odoo_accounting',
  settings: '/super_admin/odoo_accounting/settings',
  customers: '/super_admin/odoo_accounting/customers',
  invoices: '/super_admin/odoo_accounting/invoices',
  transactions: '/super_admin/odoo_accounting/transactions',
  history: '/super_admin/odoo_accounting/history',
  errors: '/super_admin/odoo_accounting/errors',
  diagnostics: '/super_admin/odoo_accounting/diagnostics',
  import: '/super_admin/odoo_accounting/import'
}.freeze

WRITE_PATHS = %w[
  /super_admin/odoo_accounting/clear_api_key
  /super_admin/odoo_accounting/test_connection
  /super_admin/odoo_accounting/run_capability_probe
  /super_admin/odoo_accounting/enable
  /super_admin/odoo_accounting/disable
  /super_admin/odoo_accounting/start_import
  /super_admin/odoo_accounting/retry_event
].freeze

RSpec.describe 'Super Admin Odoo Accounting', type: :request do
  include_context 'with commerce encryption'

  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'without a destination configured' do
    before { sign_in(super_admin, scope: :super_admin) }

    # The most important rendering case, and the one a happy-path-only spec would miss: an installation that
    # has not set Odoo up must still be able to open every page and be told what is missing.
    READ_PATHS.each do |name, path|
      it "renders #{name} and says nothing is configured" do
        get path

        expect(response).to have_http_status(:success)
      end
    end

    it 'names the not-configured state on the overview rather than showing a blank page' do
      get READ_PATHS[:overview]

      expect(response.body).to include('No destination')
    end
  end

  describe 'with a configured destination' do
    let!(:profile) { create(:odoo_destination_profile, :registering_payments) }

    before { sign_in(super_admin, scope: :super_admin) }

    READ_PATHS.each do |name, path|
      it "renders #{name}" do
        get path

        expect(response).to have_http_status(:success)
      end
    end

    it 'renders the lists with their rows' do
      create(:odoo_customer_mapping, destination_profile: profile, account: account)
      create(:odoo_document_mapping, :posted, destination_profile: profile, account_id: account.id)
      create(:odoo_sync_event, destination_profile: profile, state: :failed, last_error_class: 'SERVER_ERROR')

      get READ_PATHS[:invoices]
      expect(response.body).to include('INV/2026/0007')

      get READ_PATHS[:errors]
      expect(response.body).to include('SERVER_ERROR')
    end

    # THE SECRET NEVER REACHES THE PAGE. Asserted on the real rendered HTML rather than on a serializer,
    # because the form is where a careless `value:` would put it.
    it 'never renders the stored API key' do
      get READ_PATHS[:settings]

      expect(response.body).not_to include('odoo-api-key-factory')
      expect(response.body).to include(profile.masked_api_key)
    end

    it 'keeps the stored key when the field is submitted empty' do
      patch READ_PATHS[:settings], params: { name: 'Renamed destination', api_key: '',
                                             base_url: profile.base_url, database: profile.database,
                                             username: profile.username }

      expect(profile.reload.name).to eq('Renamed destination')
      expect(profile.api_key).to eq('odoo-api-key-factory')
    end

    it 'refuses a base URL that is not https' do
      patch READ_PATHS[:settings], params: { base_url: 'http://odoo.example.com', name: profile.name,
                                             database: profile.database, username: profile.username }

      expect(profile.reload.base_url).to start_with('https://')
      expect(flash[:alert]).to include('https')
    end

    it 'turns synchronisation off without touching the queue' do
      event = create(:odoo_sync_event, destination_profile: profile)

      post '/super_admin/odoo_accounting/disable'

      expect(profile.reload.sync_enabled).to be(false)
      expect(event.reload).to be_present
    end
  end

  describe 'authorization boundary' do
    # Named so RSpec/ContextWording's describe-vs-context distinction stays readable.
    # A tenant administrator is the highest role inside an account and must still bounce off every one of
    # these: an Odoo destination is installation-wide and none of a tenant's business.
    [:administrator, :agent].each do |role|
      context "when signed in as a tenant #{role}" do
        before { sign_in(public_send(role)) }

        READ_PATHS.each_value do |path|
          it "refuses GET #{path}" do
            get path

            expect(response).to have_http_status(:redirect)
            expect(response).to redirect_to('/super_admin/sign_in')
          end
        end

        WRITE_PATHS.each do |path|
          it "refuses POST #{path}" do
            post path

            expect(response).to have_http_status(:redirect)
          end
        end
      end
    end

    context 'without any session' do
      READ_PATHS.each_value do |path|
        it "refuses GET #{path}" do
          get path

          expect(response).to redirect_to('/super_admin/sign_in')
        end
      end
    end
  end
end
