require 'rails_helper'

# THE PARTNER HALF OF THE SEND DECISION (docs/partner-consent/ADR-001-partner-scoped-consent.md).
#
# TWO INSTALLATIONS THROUGHOUT, which is the minimum that can demonstrate the property the
# whole subsystem exists for: a grant captured by one partner installation authorises nothing
# for another, even when both sit in the same Lynomia account and name the same shopper. A
# single-installation fixture cannot tell a correct implementation from one that ignores scope
# altogether.
RSpec.describe Partners::Eligibility do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:app) { create(:platform_app) }
  let(:store_a) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-1') }
  let(:store_b) { create(:commerce_store, account: account, provider: 'salla', external_store_id: 'sa-2') }
  let(:shopper) { create(:contact, account: account, name: 'Shopper') }

  def consent(store, state, **scope)
    contact = scope.fetch(:contact, shopper)
    PartnerConsent.create!(platform_app: app, account: store.account, commerce_store: store, contact: contact,
                           external_subject_id: "ext-#{contact.id}", source: 'checkout_optin',
                           purpose: scope.fetch(:purpose, :promotional), channel: scope.fetch(:channel, :any),
                           state: state, captured_at: scope.fetch(:captured_at, Time.current))
  end

  describe 'cross-partner isolation' do
    it 'does not let one installation\'s grant authorise another\'s marketing' do
      consent(store_a, :granted)

      expect(described_class.refusal(shopper, store_a, :promotional, :whatsapp)).to be_nil
      expect(described_class.refusal(shopper, store_b, :promotional, :whatsapp)).to eq(:partner_consent_missing)
    end

    # The scope is in the unique key, so the same shopper legitimately holds opposite decisions
    # for two installations. Neither leaks into the other.
    it 'keeps opposite decisions for the same shopper at two installations' do
      consent(store_a, :granted)
      consent(store_b, :withdrawn)

      expect(described_class.refusal(shopper, store_a, :promotional, :whatsapp)).to be_nil
      expect(described_class.refusal(shopper, store_b, :promotional, :whatsapp)).to eq(:partner_consent_withdrawn)
    end

    it 'refuses a contact that does not belong to the installation\'s account' do
      other = create(:contact, account: create(:account), name: 'Elsewhere')

      expect(described_class.refusal(other, store_a, :transactional, :whatsapp)).to eq(:partner_scope_mismatch)
    end

    # The row itself refuses to exist across an account boundary, so the denormalised
    # account_id eligibility filters on can never be a lie.
    it 'will not store a consent whose store and account disagree' do
      record = PartnerConsent.new(platform_app: app, account: create(:account), commerce_store: store_a,
                                  contact: shopper, external_subject_id: 'x', purpose: :promotional,
                                  channel: :any, state: :granted, source: 'checkout_optin', captured_at: Time.current)

      expect(record).not_to be_valid
      expect(record.errors[:commerce_store]).to include('belongs to a different account')
    end
  end

  describe 'scope matching' do
    it 'does not let a transactional grant authorise marketing' do
      consent(store_a, :granted, purpose: :transactional)

      expect(described_class.refusal(shopper, store_a, :promotional, :whatsapp)).to eq(:partner_consent_missing)
    end

    # A capture that named a channel covers that channel only, because that is all the
    # customer was shown. A capture that named none covers any of them.
    it 'honours the channel the consent was captured for' do
      consent(store_a, :granted, channel: :email)

      expect(described_class.refusal(shopper, store_a, :promotional, :email)).to be_nil
      expect(described_class.refusal(shopper, store_a, :promotional, :whatsapp)).to eq(:partner_consent_missing)
    end

    it 'treats a channel-agnostic grant as covering every channel' do
      consent(store_a, :granted, channel: :any)

      %i[whatsapp sms email].each do |channel|
        expect(described_class.refusal(shopper, store_a, :promotional, channel)).to be_nil
      end
    end

    # A withdrawal reaches exactly as far as its own scope. Turning off one store's marketing
    # says nothing about the parcel notifications the shopper still wants.
    it 'does not let a marketing withdrawal block a transactional message' do
      consent(store_a, :withdrawn, purpose: :promotional)

      expect(described_class.refusal(shopper, store_a, :transactional, :whatsapp)).to be_nil
    end

    it 'needs no grant for a transactional message' do
      expect(described_class.refusal(shopper, store_a, :transactional, :whatsapp)).to be_nil
    end

    it 'separates a suppression from a withdrawal, because an operator may clear only one' do
      consent(store_a, :suppressed)

      expect(described_class.refusal(shopper, store_a, :promotional, :whatsapp)).to eq(:partner_suppressed)
    end
  end

  describe 'installation lifecycle' do
    # Stricter than Commerce::Store.connected, which still includes these two. The question
    # here is whether the integration may vouch for a NEW outbound message right now.
    %i[disabled needs_reauth disconnected].each do |status|
      it "refuses every send while the installation is #{status}" do
        consent(store_a, :granted)
        store_a.update!(status: status)

        expect(described_class.refusal(shopper, store_a, :promotional, :whatsapp)).to eq(:installation_revoked)
        expect(described_class.refusal(shopper, store_a, :transactional, :whatsapp)).to eq(:installation_revoked)
      end
    end

    it 'keeps the evidence after revocation, and only withdraws the authority to act on it' do
      consent(store_a, :granted)
      store_a.update!(status: :disconnected)

      expect(PartnerConsent.where(commerce_store: store_a).granted.count).to eq(1)
    end
  end

  # The relation form resolves an audience; the per-contact form decides at the send boundary.
  # Two expressions of one rule are a drift hazard, so they are asserted to agree.
  describe 'agreement between .filter and .refusal' do
    let(:granted) { create(:contact, account: account, name: 'Granted') }
    let(:withdrew) { create(:contact, account: account, name: 'Withdrew') }
    let(:silent) { create(:contact, account: account, name: 'Silent') }
    let(:everyone) { [granted, withdrew, silent] }

    before do
      consent(store_a, :granted, contact: granted)
      consent(store_a, :withdrawn, contact: withdrew)
    end

    %i[transactional promotional].each do |purpose|
      it "matches the per-contact decision for a #{purpose} send" do
        relation = account.contacts.where(id: everyone.map(&:id))

        reachable = described_class.filter(relation, store_a, purpose, :whatsapp).to_a
        allowed = everyone.select { |c| described_class.allows?(c, store_a, purpose, :whatsapp) }

        expect(reachable).to match_array(allowed)
      end
    end

    it 'returns nobody at all while the installation is revoked' do
      store_a.update!(status: :disconnected)

      expect(described_class.filter(account.contacts, store_a, :transactional, :whatsapp)).to be_empty
    end
  end
end
