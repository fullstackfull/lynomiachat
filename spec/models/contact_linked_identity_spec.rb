require 'rails_helper'

# The other half of the deterministic guarantee (docs/p10/03-unified-customer-identity.md §4). `contacts` holds
# one phone number and one email address per contact in its own unique columns, `contact_identities` holds the
# rest, and no index spans both -- so a contact must not be given a value another contact has linked.
RSpec.describe Contact do
  let(:account) { create(:account) }
  let(:owner) { create(:contact, account: account) }

  before do
    create(:contact_identity, account: account, contact: owner, identity_type: :phone, value: '+96560000002')
    create(:contact_identity, :email, account: account, contact: owner, value: 'dana.alt@example.com')
  end

  it 'refuses a phone number another contact has linked' do
    other = build(:contact, account: account, phone_number: '+96560000002')

    expect(other).not_to be_valid
    expect(other.errors[:phone_number].join).to include('already linked')
  end

  it 'refuses an email another contact has linked' do
    other = build(:contact, account: account, email: 'dana.alt@example.com')

    expect(other).not_to be_valid
    expect(other.errors[:email].join).to include('already linked')
  end

  it 'refuses it on update as well as on create' do
    other = create(:contact, account: account)

    expect { other.update!(phone_number: '+96560000002') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'lets the contact that owns the link take the value as its own primary field' do
    expect(owner.update(phone_number: '+96560000002')).to be(true)
  end

  it 'does not look outside the account' do
    expect(build(:contact, account: create(:account), phone_number: '+96560000002')).to be_valid
  end

  it 'costs no query when neither column changes' do
    contact = create(:contact, account: account, name: 'Dana')

    expect(ContactIdentity).not_to receive(:where)

    contact.update!(name: 'Dana Al-Sabah')
  end

  it 'ignores a blank value, which the model stores as NULL' do
    expect(build(:contact, account: account, phone_number: '', email: '')).to be_valid
  end
end
