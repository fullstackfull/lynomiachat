require 'rails_helper'

RSpec.describe Contacts::IdentityLinker do
  subject(:link) do
    described_class.new(contact: contact, identity_type: identity_type, value: value, linked_by: agent).link
  end

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:identity_type) { :phone }
  let(:value) { '+96550000001' }

  before { account.enable_features('lynomia_unified_identity') && account.save! }

  describe 'the account feature' do
    it 'records nothing when the account does not have it' do
      account.disable_features('lynomia_unified_identity')
      account.save!

      expect(link.status).to eq(:disabled)
      expect(ContactIdentity.count).to eq(0)
    end
  end

  describe 'a value nobody owns' do
    it 'records it against the contact, with who linked it' do
      expect(link.status).to eq(:linked)
      expect(link.identity).to have_attributes(contact_id: contact.id, identity_type: 'phone',
                                               value: '+96550000001', source: 'agent_linked', linked_by_id: agent.id)
    end

    it 'records an email in lower case, whatever case it arrives in' do
      result = described_class.new(contact: contact, identity_type: :email, value: '  Dana.Alt@Example.COM ').link

      expect(result.identity.value).to eq('dana.alt@example.com')
    end
  end

  describe 'a value the contact already has' do
    it 'is a no-op when it is already a row' do
      first = link
      again = described_class.new(contact: contact, identity_type: :phone, value: value).link

      expect(again.status).to eq(:already_linked)
      expect(again.identity.id).to eq(first.identity.id)
      expect(contact.contact_identities.count).to eq(1)
    end

    it 'is a no-op when it is the contact own primary field' do
      contact.update!(phone_number: '+96550000001')

      expect(link.status).to eq(:already_linked)
      expect(ContactIdentity.count).to eq(0)
    end
  end

  describe 'a value another contact owns' do
    it 'refuses when it is that contact primary field, and names it' do
      other = create(:contact, account: account, phone_number: '+96550000001')

      expect(link.status).to eq(:conflict)
      expect(link.conflict_contact_id).to eq(other.id)
      expect(ContactIdentity.count).to eq(0)
    end

    it 'refuses when it is already linked to that contact' do
      other = create(:contact, account: account)
      create(:contact_identity, account: account, contact: other, identity_type: :phone, value: '+96550000001')

      expect(link.status).to eq(:conflict)
      expect(link.conflict_contact_id).to eq(other.id)
    end

    it 'does not look outside the account' do
      other_account = create(:account)
      create(:contact, account: other_account, phone_number: '+96550000001')

      expect(link.status).to eq(:linked)
    end

    it 'reports the conflict rather than raising when the row appears between the check and the insert' do
      other = create(:contact, account: account)
      allow(ContactIdentity).to receive(:create!).and_wrap_original do |*|
        create(:contact_identity, account: account, contact: other, identity_type: :phone, value: '+96550000001')
        raise ActiveRecord::RecordNotUnique, 'duplicate key'
      end

      expect(link.status).to eq(:conflict)
      expect(link.conflict_contact_id).to eq(other.id)
    end
  end

  describe 'normalization' do
    it 'refuses a local number with no country rather than guessing one' do
      result = described_class.new(contact: contact, identity_type: :phone, value: '0551112233').link

      expect(result.status).to eq(:invalid)
      expect(ContactIdentity.count).to eq(0)
    end

    it 'uses the country the contact already carries' do
      contact.update!(additional_attributes: { 'country_code' => 'KW' })

      result = described_class.new(contact: contact, identity_type: :phone, value: '50000001').link

      expect(result.identity.value).to eq('+96550000001')
    end

    it 'turns 00 into + the way a keypad writes it' do
      result = described_class.new(contact: contact, identity_type: :phone, value: '0096550000001').link

      expect(result.identity.value).to eq('+96550000001')
    end

    # The CSV importer stores numbers that are well formed without being real numbers, and a merge has to be
    # able to carry one of those across. See Contacts::IdentityLinker#normalized_phone.
    it 'keeps a well-formed number that carries its own country even when it is not a real number' do
      result = described_class.new(contact: contact, identity_type: :phone, value: '+99999999999').link

      expect(result.status).to eq(:linked)
      expect(result.identity.value).to eq('+99999999999')
    end

    it 'refuses something that is not an email address' do
      expect(described_class.new(contact: contact, identity_type: :email, value: 'dana@').link.status).to eq(:invalid)
    end

    it 'refuses a type the model does not have' do
      expect(described_class.new(contact: contact, identity_type: :passport, value: 'X1').link.status).to eq(:invalid)
    end
  end
end
