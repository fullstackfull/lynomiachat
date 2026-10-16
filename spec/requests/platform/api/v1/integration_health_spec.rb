require 'rails_helper'

# WHAT A PARTNER MAY LEARN ABOUT ITS OWN INSTALLATION, and what it may not learn about
# anybody else's.
#
# The authorization examples are the point of this file. PlatformController applies its
# resource and permissible filters with `only: [:update, :show, :destroy]`, so an endpoint
# added under a differently-named action gets neither and answers any valid token for any
# account id in the URL. These examples would catch that, and catch a later rename too.
RSpec.describe 'Platform Integration Health API', type: :request do
  include_context 'with commerce encryption'

  let!(:partner_app) { create(:platform_app) }
  let!(:account) { create(:account) }
  let!(:store) do
    create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'localhost:1', name: 'Shop')
  end
  let(:url) { "/platform/api/v1/accounts/#{account.id}/integration_health" }
  let(:headers) { { api_access_token: partner_app.access_token.token } }
  let(:body) { response.parsed_body }

  before { create(:platform_app_permissible, platform_app: partner_app, permissible: account) }

  describe 'authorization' do
    it 'refuses a caller with no token at all' do
      get url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses a token that is not a platform app' do
      get url, headers: { api_access_token: create(:user).access_token.token }

      expect(response).to have_http_status(:unauthorized)
    end

    # The hole this endpoint would have had if the action were named anything but `show`.
    it 'refuses an account this app was never granted' do
      other = create(:account)

      get "/platform/api/v1/accounts/#{other.id}/integration_health", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    # Whether an id exists here is not something an unauthorized caller gets to learn, so a
    # missing account answers exactly as a forbidden one does.
    it 'answers a missing account the same way as a forbidden one' do
      get '/platform/api/v1/accounts/0/integration_health', headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(body['error_code']).to eq('non_permissible_resource')
    end
  end

  describe 'the payload' do
    before { get url, headers: headers }

    it 'answers for the installation it was asked about' do
      expect(response).to have_http_status(:success)
      expect(body['account']).to include('id' => account.id)
      expect(body['installations'].first).to include('external_store_id' => 'localhost:1', 'status' => 'active')
    end

    # `unknown` rather than green: recording began when the feature was deployed and
    # reconstructs nothing, so a store nobody has called yet has no observation to report.
    it 'does not call a store that has never been observed healthy' do
      expect(body['installations'].first['health']).to include('api_state' => 'unknown')
      expect(body['status']).to eq('unknown')
    end

    it 'carries no credential, anywhere in the payload' do
      expect(response.body).not_to include(store.credentials.to_s) if store.credentials.present?
      expect(response.body).not_to match(/credential|password|token|secret/i)
    end
  end

  describe 'what it reports' do
    it 'reads a store an administrator has taken out of service as critical' do
      store.update!(status: :needs_reauth)

      get url, headers: headers

      expect(body['status']).to eq('critical')
      expect(body['installations'].first['status']).to eq('needs_reauth')
    end

    it 'categorises the open signals it is allowed to show' do
      Operations::SignalRecorder.new(source: 'commerce_store', account: account, subject: store)
                                .record('connection_failed', severity: :critical, reason: 'provider refused')

      get url, headers: headers

      expect(body['signals']).to include('open' => 1, 'by_source' => { 'commerce_store' => 1 })
      expect(body['signals']['recent'].first)
        .to include('source' => 'commerce_store', 'signal' => 'connection_failed', 'severity' => 'critical')
    end

    # THE COUNT IS THE COUNT, NOT THE LENGTH OF THE LIST.
    #
    # `recent` is capped at SIGNAL_LIMIT so a page does not render thirty rows. `open` used to
    # be that capped list's size, so it saturated at 20 while `by_source` -- in the same
    # payload, about the same installation -- went on summing to the real number. Both
    # consoles render `open` as "open issues", so an operator was shown a figure that
    # contradicted the one beside it precisely when an installation was worst off.
    it 'counts every open signal even though it lists only the most recent' do
      over = Operations::IntegrationHealth::SIGNAL_LIMIT + 3

      over.times do |i|
        Operations::SignalRecorder.new(source: 'commerce_store', account: account,
                                       subject: create(:commerce_store, account: account,
                                                                        external_store_id: "overflow-#{i}"))
                                  .record('connection_failed', severity: :critical, reason: 'provider refused')
      end

      get url, headers: headers

      expect(body['signals']['open']).to eq(over)
      expect(body['signals']['by_source']['commerce_store']).to eq(over)
      expect(body['signals']['recent'].size).to eq(Operations::IntegrationHealth::SIGNAL_LIMIT)
    end

    # A workspace problem that is not this integration's is Lynomia's business with the
    # merchant, not the partner's.
    it 'leaves out a signal about something the partner cannot act on' do
      inbox = create(:inbox, account: account)
      Operations::SignalRecorder.new(source: 'email_channel', account: account, subject: inbox)
                                .record('authentication_failed', reason: 'mailbox rejected the password')

      get url, headers: headers

      expect(body['signals']['open']).to eq(0)
    end

    # Counts, never who decided what: a health endpoint is not where a shopper's consent is read.
    it 'reports the consent feed as counts and a timestamp' do
      get url, headers: headers

      expect(body['consent']).to include('decisions_held' => 0, 'blocking' => 0, 'last_event_at' => nil)
    end
  end

  # Two integrations on one workspace must not read each other's consent traffic through an
  # endpoint that is nominally about health.
  it 'confines the consent figures to the calling app' do
    other_app = create(:platform_app)
    contact = create(:contact, account: account)
    PartnerConsent.create!(platform_app: other_app, account: account, commerce_store: store, contact: contact,
                           external_subject_id: 'cust-9', purpose: :promotional, channel: :any,
                           state: :granted, source: 'checkout_optin', captured_at: Time.current)

    get url, headers: headers

    expect(body['consent']['decisions_held']).to eq(0)
  end
end
