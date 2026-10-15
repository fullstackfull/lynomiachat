require 'rails_helper'

# WHAT HAPPENS TO A CONSENT RECORD WHEN THE THING IT IS ABOUT GOES AWAY.
#
# `partner_consents` and `partner_consent_events` were created with plain `foreign_key: true`
# on contacts, stores, accounts and apps, which in Postgres is ON DELETE NO ACTION -- the
# delete is REFUSED. Every other contact-owned table in this overlay says what should happen
# (`campaign_recipients`, `commerce_customer_links` and `contact_identities` all cascade),
# and these two said nothing, so:
#
#   * deleting a contact who had ever opted in at a partner checkout raised
#     ActiveRecord::InvalidForeignKey -- a merchant could not delete their own customer, and
#     neither could an erasure request;
#   * re-claiming a store another account had disconnected raised the same, because
#     Commerce::StoreConnection#claim destroys the released row.
#
# CASCADE, NOT NULLIFY, and not RESTRICT. A consent decision is a fact ABOUT A PERSON at an
# installation; with the person erased there is nobody to message and keeping the decision
# would be keeping personal data past the erasure that was meant to remove it. The same
# reasoning the native link table already applies.
RSpec.describe 'partner consent lifecycle', type: :model do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:app) { create(:platform_app) }
  let(:store) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-1') }
  let(:contact) { create(:contact, account: account, name: 'Shopper') }

  def consent(**overrides)
    PartnerConsent.create!({ platform_app: app, account: account, commerce_store: store, contact: contact,
                             external_subject_id: 'cust-1', source: 'checkout_optin', purpose: :promotional,
                             channel: :any, state: :granted, captured_at: Time.current }.merge(overrides))
  end

  def event
    PartnerConsentEvent.create!(platform_app: app, account: account, commerce_store: store, contact: contact,
                                external_subject_id: 'cust-1', decision_ref: SecureRandom.uuid, source: 'checkout_optin',
                                purpose: :promotional, channel: :any, state: :granted, captured_at: Time.current,
                                received_at: Time.current, outcome: :applied)
  end

  it 'lets a contact be deleted, and takes their decisions with them' do
    consent
    event

    expect { contact.destroy! }.to change(PartnerConsent, :count).by(-1)
                                                                 .and change(PartnerConsentEvent, :count).by(-1)
  end

  # Commerce::StoreConnection#claim destroys a row another account has disconnected so this
  # account can take the same store. A consent captured under the old connection has no
  # meaning for the new one, and it must not block the claim.
  it 'lets a disconnected store be released, and takes its decisions with it' do
    consent
    event

    expect { store.destroy! }.to change(PartnerConsent, :count).by(-1)
                                                               .and change(PartnerConsentEvent, :count).by(-1)
  end

  it 'lets an account be deleted' do
    consent
    event

    expect { account.destroy! }.not_to raise_error
  end

  # The operator who recorded a decision is not what the decision is about, so deleting them
  # leaves the evidence and forgets who typed it -- the same rule
  # `commerce_customer_links.confirmed_by_id` already follows.
  it 'keeps a decision when the operator who recorded it is deleted' do
    operator = create(:user, account: account, role: :administrator)
    row = consent(recorded_by: operator)

    operator.destroy!

    expect(row.reload.recorded_by_id).to be_nil
  end
end
