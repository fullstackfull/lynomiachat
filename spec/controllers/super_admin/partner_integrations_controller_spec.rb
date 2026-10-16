require 'rails_helper'

# P6C. PARTNER INTEGRATION ADMINISTRATION, for a Lynomia operator.
#
# Two things are asserted besides the content. One is the Super Admin boundary, which is the
# only authorization this surface has. The other is the navigation partial: Administrate
# enumerates every controller under super_admin/ and asks each for an index route and a
# dashboard, so a hand-written one that is not in the exclusion list raises inside the shared
# partial and breaks EVERY Super Admin page. Rendering any other page is what catches that,
# which is why one example here loads Operations instead.
RSpec.describe 'Super Admin Partner Integrations', type: :request do
  include_context 'with commerce encryption'

  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let!(:partner_app) { create(:platform_app, name: 'Store Syria') }
  let!(:store) do
    create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'localhost:1', name: 'Shop')
  end

  before { create(:platform_app_permissible, platform_app: partner_app, permissible: account) }

  describe 'the Super Admin boundary' do
    it 'redirects an unauthenticated caller away from both pages' do
      ['/super_admin/partner_integrations', '/super_admin/partner_integrations/app'].each do |path|
        get path

        expect(response).to have_http_status(:redirect)
      end
    end

    it 'does not let a tenant administrator in' do
      sign_in(create(:user, account: account, role: :administrator), scope: :user)

      get '/super_admin/partner_integrations'

      expect(response).to have_http_status(:redirect)
    end
  end

  context 'when signed in as an operator' do
    before { sign_in(super_admin, scope: :super_admin) }

    # THE OBLIGATION THAT SHIPS WITH A HAND-WRITTEN CONTROLLER. Without the exclusion this
    # raises, and it raises on every Super Admin page rather than only on the new one.
    it 'does not break the navigation on other Super Admin pages' do
      get '/super_admin/operations'

      expect(response).to have_http_status(:success)
    end

    it 'lists every registered integration with what it holds' do
      get '/super_admin/partner_integrations'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Store Syria')
    end

    it 'says plainly that it changes nothing, and points at what does' do
      get '/super_admin/partner_integrations'

      expect(response.body).to include('Read only')
      expect(response.body).to include('/super_admin/platform_apps')
    end

    describe 'one integration in full' do
      before { get "/super_admin/partner_integrations/app?id=#{partner_app.id}" }

      it 'shows the installations it holds and how they are doing' do
        expect(response).to have_http_status(:success)
        expect(response.body).to include('localhost:1')
        expect(response.body).to include('Workspaces')
      end

      it 'counts what it is permitted rather than listing the people' do
        expect(response.body).to include('Permissions')
        expect(response.body).to include('Accounts')
      end

      it 'carries no credential anywhere on the page' do
        expect(response.body).not_to match(/lsc_|api_access_token|provider_config/)
      end
    end

    it 'shows an open issue against one of the integration workspaces' do
      Operations::SignalRecorder.new(source: 'commerce_store', account: account, subject: store)
                                .record('connection_failed', severity: :critical, reason: 'provider refused')

      get '/super_admin/partner_integrations'

      expect(response.body).to include('Open issues')
    end

    # A signal the partner cannot act on is the merchant's business with Lynomia, and the same
    # filter applies here as in the partner-facing projection -- they read one set of facts.
    it 'leaves out a workspace problem that is not this integration' do
      Operations::SignalRecorder.new(source: 'email_channel', account: account, subject: create(:inbox, account: account))
                                .record('authentication_failed', reason: 'mailbox rejected the password')

      get "/super_admin/partner_integrations/app?id=#{partner_app.id}"

      expect(response.body).to include('Open issues: <strong>0</strong>')
    end

    it 'sends an operator following a stale link back to the list' do
      get '/super_admin/partner_integrations/app?id=0'

      expect(response).to redirect_to('/super_admin/partner_integrations')
      expect(flash[:alert]).to eq('That integration no longer exists.')
    end
  end
end
