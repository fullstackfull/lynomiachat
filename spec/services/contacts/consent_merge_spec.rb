require 'rails_helper'

# MERGING TWO CONTACTS MUST NEVER LOSE A REFUSAL.
#
# Neither consent table was in Contacts::MergeRelocation's move lists, so the mergee's
# decisions were left on a record about to be deleted: a shopper who had replied STOP under
# one of their two contact records came out of a merge with that STOP gone. Every protection
# at the send boundary is defeated by one click of Merge if this is wrong, which is why the
# examples below are written as "the refusal survives" rather than "the rows moved".
RSpec.describe Contacts::ConsentMerge do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:base) { create(:contact, account: account, name: 'Base') }
  let(:mergee) { create(:contact, account: account, name: 'Mergee') }
  let(:partner_app) { create(:platform_app) }
  let(:store) { create(:commerce_store, account: account, provider: 'storesyria', external_store_id: 'sy-1') }

  def native(contact, state, purpose: :promotional)
    Commerce::MessagingConsents.record(
      account: account, contact: contact,
      decision: Commerce::MessagingConsents::Decision.new(state: state, source: 'shopper_keyword',
                                                          purposes: [purpose.to_s])
    )
  end

  def partner(contact, state, scope_store: store, channel: :any)
    PartnerConsent.create!(platform_app: partner_app, account: account, commerce_store: scope_store,
                           contact: contact, external_subject_id: "ext-#{contact.id}", purpose: :promotional,
                           channel: channel, state: state, source: 'checkout_optin', captured_at: Time.current)
  end

  def merge! = described_class.perform(base: base, mergee: mergee)

  def native_state(purpose: :promotional)
    Commerce::MessagingConsent.find_by(contact_id: base.id, purpose: purpose)&.state
  end

  describe 'the strongest refusal wins' do
    it 'keeps the mergee\'s withdrawal over the base\'s grant' do
      native(base, :granted)
      native(mergee, :withdrawn)

      merge!

      expect(native_state).to eq('withdrawn')
    end

    it 'keeps the base\'s withdrawal when the mergee granted' do
      native(base, :withdrawn)
      native(mergee, :granted)

      merge!

      expect(native_state).to eq('withdrawn')
    end

    it 'keeps a suppression over a withdrawal, in either direction' do
      native(base, :withdrawn)
      native(mergee, :suppressed)

      merge!

      expect(native_state).to eq('suppressed')
    end

    it 'never downgrades a suppression the base already held' do
      native(base, :suppressed)
      native(mergee, :granted)

      merge!

      expect(native_state).to eq('suppressed')
    end
  end

  describe 'decisions the base does not hold' do
    it 'carries a decision across when the base has none for that scope' do
      native(mergee, :withdrawn)

      merge!

      expect(native_state).to eq('withdrawn')
    end

    it 'keeps the classes apart' do
      native(mergee, :withdrawn, purpose: :promotional)
      native(base, :granted, purpose: :transactional)

      merge!

      expect(native_state(purpose: :promotional)).to eq('withdrawn')
      expect(native_state(purpose: :transactional)).to eq('granted')
    end
  end

  # A refusal nobody can account for is the shape of record that gets overruled later by
  # somebody who cannot see why it exists.
  it 'brings the winning decision\'s evidence with it' do
    native(base, :granted)
    losing = Commerce::MessagingConsent.find_by(contact_id: base.id)
    native(mergee, :withdrawn)
    winner = Commerce::MessagingConsent.find_by(contact_id: mergee.id)

    merge!

    survivor = Commerce::MessagingConsent.find_by(contact_id: base.id)
    expect(survivor.source).to eq(winner.source)
    expect(survivor.decided_at).to be_within(1.second).of(winner.decided_at)
    expect(survivor.source).not_to eq(losing.source) if losing.source != winner.source
  end

  describe 'partner consent' do
    it 'keeps a partner withdrawal over a partner grant at the same installation' do
      partner(base, :granted)
      partner(mergee, :withdrawn)

      merge!

      expect(PartnerConsent.find_by(contact_id: base.id, commerce_store: store).state).to eq('withdrawn')
    end

    # Scope survives the merge: two installations stay two scopes, which is the property the
    # unique key exists for.
    it 'does not let one installation\'s decision leak into another' do
      other = create(:commerce_store, account: account, provider: 'salla', external_store_id: 'sa-2')
      partner(base, :granted, scope_store: other)
      partner(mergee, :withdrawn, scope_store: store)

      merge!

      expect(PartnerConsent.find_by(contact_id: base.id, commerce_store: store).state).to eq('withdrawn')
      expect(PartnerConsent.find_by(contact_id: base.id, commerce_store: other).state).to eq('granted')
    end

    it 'keeps channels apart' do
      partner(base, :granted, channel: :email)
      partner(mergee, :withdrawn, channel: :sms)

      merge!

      expect(PartnerConsent.find_by(contact_id: base.id, channel: :email).state).to eq('granted')
      expect(PartnerConsent.find_by(contact_id: base.id, channel: :sms).state).to eq('withdrawn')
    end
  end

  # A row still pointing at a contact that is about to be deleted is the original defect.
  it 'leaves nothing behind on the mergee' do
    native(base, :granted)
    native(mergee, :withdrawn)
    partner(mergee, :withdrawn)

    merge!

    expect(Commerce::MessagingConsent.where(contact_id: mergee.id)).to be_empty
    expect(PartnerConsent.where(contact_id: mergee.id)).to be_empty
  end

  # The end-to-end property, through the real merge path rather than this service alone.
  describe 'through the full merge' do
    it 'survives ContactMergeAction, so the send boundary still refuses afterwards' do
      native(base, :granted)
      native(mergee, :withdrawn)

      Contacts::MergeRelocation.new(base: base, mergee: mergee).perform

      expect(Commerce::MessagingEligibility.refusal(base.reload, :promotional)).to eq(:consent_withdrawn)
    end
  end
end
