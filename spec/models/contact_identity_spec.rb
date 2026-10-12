require 'rails_helper'

RSpec.describe ContactIdentity do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  describe 'uniqueness' do
    it 'refuses the same value for a second contact in the account' do
      create(:contact_identity, account: account, contact: contact, identity_type: :phone, value: '+96550000001')
      duplicate = build(:contact_identity, account: account, contact: create(:contact, account: account),
                                           identity_type: :phone, value: '+96550000001')

      expect(duplicate).not_to be_valid
    end

    it 'allows the same value in a different account, because identity is per account' do
      create(:contact_identity, account: account, contact: contact, identity_type: :phone, value: '+96550000001')
      other = create(:account)

      expect(build(:contact_identity, account: other, contact: create(:contact, account: other),
                                      identity_type: :phone, value: '+96550000001')).to be_valid
    end

    it 'lets one contact hold several numbers and addresses, which is the whole point of the table' do
      create(:contact_identity, account: account, contact: contact, identity_type: :phone, value: '+96550000001')
      create(:contact_identity, account: account, contact: contact, identity_type: :phone, value: '+96560000002')
      create(:contact_identity, :email, account: account, contact: contact, value: 'second@example.com')

      expect(contact.contact_identities.count).to eq(3)
    end

    it 'is enforced by the database, not only by the validation' do
      create(:contact_identity, account: account, contact: contact, identity_type: :phone, value: '+96550000001')
      row = build(:contact_identity, account: account, contact: create(:contact, account: account),
                                     identity_type: :phone, value: '+96550000001')

      expect { row.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'format' do
    it 'holds a phone number only in the shape contacts.phone_number accepts' do
      expect(build(:contact_identity, account: account, contact: contact, identity_type: :phone,
                                      value: '0551112233')).not_to be_valid
    end

    it 'holds an email only when it is an email' do
      expect(build(:contact_identity, account: account, contact: contact, identity_type: :email,
                                      value: 'not-an-email')).not_to be_valid
    end
  end

  it 'goes with its contact' do
    identity = create(:contact_identity, account: account, contact: contact)

    contact.destroy!

    expect(described_class.where(id: identity.id)).not_to exist
  end
end
