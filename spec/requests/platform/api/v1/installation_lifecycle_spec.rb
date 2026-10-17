require 'rails_helper'

# THE TRANSITION CHANNEL, AND THE HOLE IT CLOSES.
#
# Before this, a partner revoking an installation tore down the account grant and left
# `commerce_stores.status` at `active`. Partners::Eligibility went on authorising that
# installation's campaigns indefinitely, and the operator who revoked it had every reason to
# think they had stopped it. The last example here is that hole, asserted as closed.
RSpec.describe 'Platform Installation Lifecycle API', type: :request do
  include_context 'with commerce encryption'

  let!(:partner_app) { create(:platform_app) }
  let!(:account) { create(:account) }
  let!(:store) do
    create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'localhost:1', name: 'Shop')
  end
  let(:url) { "/platform/api/v1/accounts/#{account.id}/installation_lifecycle" }
  let(:headers) { { api_access_token: partner_app.access_token.token } }
  let(:body) { response.parsed_body }

  def ask(transition, overrides = {})
    put url, params: { provider: 'storesyria', external_store_id: 'localhost:1',
                       transition: transition }.merge(overrides), headers: headers
  end

  before { create(:platform_app_permissible, platform_app: partner_app, permissible: account) }

  describe 'authorization' do
    it 'refuses a caller with no token' do
      put url, params: { provider: 'storesyria', external_store_id: 'localhost:1', transition: 'suspend' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an account this app was never granted' do
      other = create(:account)

      put "/platform/api/v1/accounts/#{other.id}/installation_lifecycle",
          params: { provider: 'storesyria', external_store_id: 'x', transition: 'suspend' }, headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    # A partner naming another account's store does not reach it: the lookup is scoped to the
    # account it was authorised for, so this is a 404 and not somebody else's store suspended.
    it 'cannot reach an installation belonging to another account' do
      other = create(:account)
      create(:commerce_store, account: other, provider: 'storesyria', external_store_id: 'elsewhere:9')

      ask('suspend', external_store_id: 'elsewhere:9')

      expect(response).to have_http_status(:not_found)
      expect(Commerce::Store.find_by(external_store_id: 'elsewhere:9')).to be_active
    end
  end

  describe 'validation at the boundary' do
    it 'refuses a transition it does not define' do
      ask('obliterate')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error_code']).to eq('unknown_transition')
      expect(store.reload).to be_active
    end

    it 'refuses a request with no transition at all' do
      put url, params: { provider: 'storesyria', external_store_id: 'localhost:1' }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error_code']).to eq('invalid_request')
    end
  end

  describe 'the transitions' do
    it 'suspends an installation' do
      ask('suspend', reason: 'billing hold', actor: 'operator@storesyria')

      expect(response).to have_http_status(:success)
      expect(body).to include('status' => 'disabled', 'applied' => true)
      expect(store.reload).to be_disabled
    end

    it 'decommissions an installation' do
      ask('disconnect')

      expect(store.reload).to be_disconnected
    end

    # The partner's outbox is at-least-once like every other delivery here, so a repeat must
    # not be an error the caller has to interpret.
    it 'is a successful no-op when the installation is already in that state' do
      ask('suspend')
      ask('suspend')

      expect(response).to have_http_status(:success)
      expect(body).to include('status' => 'disabled', 'applied' => false)
    end

    # A PARTNER MUST NOT BE ABLE TO SHUT A DOOR ON THE MERCHANT'S SIDE.
    #
    # `disconnect` drops the credentials and leaves the row `disconnected` precisely so the
    # merchant can reconnect their store, and Commerce::StoreConnection#claim refuses any row
    # that is NOT disconnected. A suspend aimed at a store the merchant had already
    # disconnected therefore rewrote it to `disabled` with no credentials, and the merchant
    # could never reconnect their own store again -- a partner action, taken for an unrelated
    # reason, closing a door on the far side of the boundary with nothing saying why.
    #
    # It is not hypothetical: AccountLinker::revoke pushes `suspend` for every link that has
    # a Lynomia account, whatever the merchant has done with the store since.
    it 'leaves a store the merchant disconnected alone, because it is already more stopped' do
      ask('disconnect')
      expect(store.reload).to be_disconnected

      ask('suspend')

      expect(response).to have_http_status(:success)
      expect(body).to include('status' => 'disconnected', 'applied' => false)
      expect(store.reload).to be_disconnected
    end

    # A resume is not a state write: it asks the provider whether the installation can
    # actually be reached, so one brought back on a dead credential is refused rather than
    # being made active and failing silently on first use.
    it 'refuses to bring back an installation whose credentials are gone' do
      store.update!(status: :disabled, credentials: nil)

      ask('resume')

      expect(response).to have_http_status(:conflict)
      expect(body['error_code']).to eq('resume_failed')
      expect(store.reload).to be_disabled
    end
  end

  describe 'the audit trail' do
    it 'records who asked, why, and which app carried it' do
      expect { ask('suspend', reason: 'unpaid invoice', actor: 'ops@storesyria') }
        .to change { Custom::AuditLog.where(comment: 'commerce.installation_lifecycle').count }.by(1)

      entry = Custom::AuditLog.where(comment: 'commerce.installation_lifecycle').last
      expect(entry.audited_changes).to include('transition' => 'suspend', 'partner_actor' => 'ops@storesyria',
                                               'reason' => 'unpaid invoice')
      expect(entry.audited_changes['requested_by_app']).to eq(partner_app.name)
    end

    # Commerce::StoreConnection writes its own row for the state change. Both are kept: one is
    # the fact, the other is the authority for it.
    it 'keeps the store own audit row beside it' do
      expect { ask('suspend') }
        .to change { Custom::AuditLog.where(comment: 'commerce.store_disabled').count }.by(1)
    end
  end

  # WHAT THIS ENDPOINT EXISTS FOR. Suspending on the partner's side used to leave the store
  # active here, and the send boundary went on saying yes.
  describe 'the send boundary afterwards' do
    let(:contact) { create(:contact, :with_phone_number, account: account) }

    it 'stops authorising that installation once it is suspended' do
      expect(Partners::Eligibility.refusal(contact, store, :transactional, :whatsapp)).to be_nil

      ask('suspend')

      expect(Partners::Eligibility.refusal(contact, store.reload, :transactional, :whatsapp)).not_to be_nil
    end
  end

  # Consent is evidence of what a person was told and agreed to. It outlives the commercial
  # arrangement that produced it, so decommissioning must not take it with the installation.
  describe 'retention' do
    it 'keeps the consent evidence when an installation is decommissioned' do
      contact = create(:contact, account: account)
      PartnerConsent.create!(platform_app: partner_app, account: account, commerce_store: store, contact: contact,
                             external_subject_id: 'cust-1', purpose: :promotional, channel: :any,
                             state: :withdrawn, source: 'checkout_optin', captured_at: Time.current)

      ask('disconnect')

      expect(PartnerConsent.where(commerce_store_id: store.id).count).to eq(1)
      expect(Commerce::Store.find_by(id: store.id)).to be_present
    end
  end
end
