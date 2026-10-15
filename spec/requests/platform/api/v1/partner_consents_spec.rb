require 'rails_helper'

# THE PARTNER WRITE API (docs/partner-consent/ADR-001-partner-scoped-consent.md).
#
# The authorization cases matter more than the happy path here. This endpoint is reached by an
# external platform holding its own token, and the two holes worth hunting are a partner
# writing into an account it was never granted, and a partner recording a decision against
# somebody who is not its customer. Both are tested as refusals rather than assumed closed.
RSpec.describe 'Platform Partner Consents API', type: :request do
  include_context 'with commerce encryption'

  let!(:partner_app) { create(:platform_app) }
  let!(:account) { create(:account) }
  let!(:store) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-1') }
  let!(:shopper) { create(:contact, account: account, name: 'Shopper') }
  let(:url) { "/platform/api/v1/accounts/#{account.id}/partner_consents" }
  let(:headers) { { api_access_token: partner_app.access_token.token } }
  let(:body) do
    { provider: 'storesyria', external_store_id: 'sy-1', external_subject_id: 'cust-77',
      decision_ref: 'evt-1', state: 'granted', purpose: 'promotional', channel: 'whatsapp',
      source: 'checkout_optin', captured_at: Time.current.iso8601, policy_version: 'v3' }
  end

  before do
    create(:platform_app_permissible, platform_app: partner_app, permissible: account)
    # The mapping the API resolves the subject through. Nothing references it directly, and
    # that IS the point: a partner names its own customer id, and this link is what turns it
    # into a Lynomia contact -- its absence is what makes the "subject this installation has
    # never seen" example a 404.
    create(:commerce_customer_link, account: account, store: store, contact: shopper,
                                    external_customer_id: 'cust-77')
  end

  describe 'authorization' do
    it 'refuses a caller with no token' do
      post url, params: body, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # THE CROSS-TENANT CASE. A real token, a real account, and no permissible between them.
    it 'refuses an app that was never granted this account' do
      stranger = create(:platform_app)

      post url, params: body, headers: { api_access_token: stranger.access_token.token }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(PartnerConsent.count).to eq(0)
    end

    it 'refuses an installation that belongs to another account' do
      other = create(:account)
      create(:platform_app_permissible, platform_app: partner_app, permissible: other)
      create(:commerce_store, account: other, provider: 'storesyria', external_store_id: 'sy-elsewhere')

      post "/platform/api/v1/accounts/#{other.id}/partner_consents",
           params: body.merge(external_store_id: 'sy-1'), headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(PartnerConsent.count).to eq(0)
    end

    # A partner names its OWN customer id and never a Lynomia contact id, so it cannot record
    # a decision about somebody who is not its customer.
    it 'refuses a subject this installation has never seen' do
      post url, params: body.merge(external_subject_id: 'nobody'), headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(PartnerConsent.count).to eq(0)
    end

    # A SUPPRESSED LINK IS AN AGENT SAYING THIS IS NOT THAT STORE'S CUSTOMER, which is the
    # whole reason the state exists -- and the link row survives, so a lookup that did not
    # exclude it found one anyway. The store could then record decisions about somebody it
    # had been told was matched in error, and was told their account-wide state in return.
    it 'refuses a subject whose link an agent suppressed' do
      Commerce::CustomerLink.find_by(commerce_store_id: store.id, contact_id: shopper.id)
                            .update!(match_source: :suppressed)

      post url, params: body, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(PartnerConsent.count).to eq(0)
    end

    it 'does not report the account-wide state of a subject whose link was suppressed' do
      Commerce::MessagingConsents.record(
        account: account, contact: shopper,
        decision: Commerce::MessagingConsents::Decision.new(state: :withdrawn, source: 'shopper_keyword')
      )
      Commerce::CustomerLink.find_by(commerce_store_id: store.id, contact_id: shopper.id)
                            .update!(match_source: :suppressed)

      get url, params: { provider: 'storesyria', external_store_id: 'sy-1' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['native']).to be_empty
    end
  end

  describe 'recording a decision' do
    it 'records a grant and says it was applied' do
      post url, params: body, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('outcome' => 'applied', 'decision_ref' => 'evt-1')

      row = PartnerConsent.sole
      expect(row).to have_attributes(commerce_store_id: store.id, contact_id: shopper.id,
                                     purpose: 'promotional', channel: 'whatsapp', state: 'granted',
                                     policy_version: 'v3', external_subject_id: 'cust-77')
    end

    it 'is idempotent on redelivery and says so' do
      2.times { post url, params: body, headers: headers, as: :json }

      expect(response.parsed_body['outcome']).to eq('duplicate').or eq('applied')
      expect(PartnerConsentEvent.count).to eq(1)
    end

    # The response distinguishes "recorded and applied" from "recorded and correctly ignored",
    # which is what lets a partner reconcile rather than guess.
    it 'reports a grant refused because the customer had withdrawn' do
      post url, params: body.merge(decision_ref: 'w1', state: 'withdrawn'), headers: headers, as: :json
      post url, params: body.merge(decision_ref: 'g2'), headers: headers, as: :json

      expect(response.parsed_body['outcome']).to eq('refused_withdrawal_dominant')
      expect(PartnerConsent.sole.state).to eq('withdrawn')
    end

    it 'applies an explicit re-consent after a withdrawal' do
      post url, params: body.merge(decision_ref: 'w1', state: 'withdrawn'), headers: headers, as: :json
      post url, params: body.merge(decision_ref: 'r1', re_consent: true), headers: headers, as: :json

      expect(response.parsed_body['outcome']).to eq('applied')
      expect(PartnerConsent.sole.state).to eq('granted')
    end
  end

  describe 'validation' do
    {
      'an unknown state' => { state: 'maybe' },
      'an unknown purpose' => { purpose: 'newsletter' },
      'an unknown channel' => { channel: 'carrier-pigeon' },
      'a missing decision_ref' => { decision_ref: '' },
      'a captured_at that is not ISO 8601' => { captured_at: 'last tuesday' }
    }.each do |name, override|
      it "refuses #{name} at the boundary" do
        post url, params: body.merge(override), headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(PartnerConsent.count).to eq(0)
      end
    end
  end

  describe 'reading back' do
    before { post url, params: body, headers: headers, as: :json }

    it 'serves this installation\'s records without any Lynomia identifier for the person' do
      get url, params: { provider: 'storesyria', external_store_id: 'sy-1' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      entry = response.parsed_body['consents'].sole
      expect(entry).to include('external_subject_id' => 'cust-77', 'state' => 'granted')
      expect(entry.keys).not_to include('contact_id', 'email', 'phone_number', 'name')
      expect(response.body).not_to include(shopper.id.to_s.rjust(8, '0'))
    end

    it 'does not show another installation\'s records' do
      other_store = create(:commerce_store, account: account, provider: 'salla', external_store_id: 'sa-2')
      other_contact = create(:contact, account: account)
      PartnerConsent.create!(platform_app: partner_app, account: account, commerce_store: other_store,
                             contact: other_contact, external_subject_id: 'salla-9', purpose: :promotional,
                             channel: :any, state: :granted, source: 'merchant', captured_at: Time.current)

      get url, params: { provider: 'storesyria', external_store_id: 'sy-1' }, headers: headers, as: :json

      expect(response.parsed_body['consents'].pluck('external_subject_id')).to eq(['cust-77'])
    end

    # THE COLLECTION A RECONCILIATION CANNOT DO WITHOUT. A shopper replying STOP on WhatsApp
    # is recorded natively, not as a partner row, and it is the single most important fact a
    # merchant's consent screen can show. A read that returned only what the partner itself
    # reported would let a partner converge happily on a view with every opt-out missing.
    it 'also serves the native decisions that apply to this installation\'s customers' do
      Commerce::MessagingConsents.record(
        account: account, contact: shopper,
        decision: Commerce::MessagingConsents::Decision.new(state: :withdrawn, source: 'shopper_keyword')
      )

      get url, params: { provider: 'storesyria', external_store_id: 'sy-1' }, headers: headers, as: :json

      native = response.parsed_body['native']
      expect(native.pluck('state').uniq).to eq(['withdrawn'])
      # Named in the PARTNER'S terms -- its own customer id, never a Lynomia contact id.
      expect(native.pluck('external_subject_id').uniq).to eq(['cust-77'])
      # Account-wide and channel-agnostic, which is the value Consents::ChangeFeed publishes
      # it under too, so a reconciling consumer and a listening one land on the same row.
      expect(native.pluck('channel').uniq).to eq(['any'])
    end

    # The same confinement the write side applies: a partner is told about its own customers
    # and nobody else's, even when they share an account.
    it 'does not serve native decisions about somebody who is not this installation\'s customer' do
      stranger = create(:contact, account: account, name: 'Not a customer here')
      Commerce::MessagingConsents.record(
        account: account, contact: stranger,
        decision: Commerce::MessagingConsents::Decision.new(state: :withdrawn, source: 'shopper_keyword')
      )

      get url, params: { provider: 'storesyria', external_store_id: 'sy-1' }, headers: headers, as: :json

      expect(response.parsed_body['native']).to be_empty
    end
  end
end
