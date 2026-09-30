require 'rails_helper'

RSpec.describe Commerce::CustomerLink do
  include_context 'with commerce encryption'

  let(:store) { create(:commerce_store) }
  let(:contact) { create(:contact, account: store.account) }

  it 'encrypts the external customer id (guest ids carry an email or phone) and can still look it up' do
    link = create(:commerce_customer_link, store: store, contact: contact, external_customer_id: 'guest:ahmed@example.com')

    raw = described_class.connection.select_value("SELECT external_customer_id FROM commerce_customer_links WHERE id = #{link.id}")
    expect(raw).not_to include('ahmed@example.com')
    expect(described_class.find_by(external_customer_id: 'guest:ahmed@example.com')).to eq(link)
  end

  it 'links a contact to at most one customer per store' do
    create(:commerce_customer_link, store: store, contact: contact)

    expect(build(:commerce_customer_link, store: store, contact: contact)).not_to be_valid
  end

  it 'rejects a contact from another account' do
    link = build(:commerce_customer_link, store: store, contact: create(:contact))

    expect(link).not_to be_valid
    expect(link.errors.details[:account]).to include(error: :invalid)
  end

  it 'rejects a store from another account' do
    link = build(:commerce_customer_link, store: create(:commerce_store), account: store.account, contact: contact)

    expect(link).not_to be_valid
  end

  it 'is removed when the contact is deleted' do
    link = create(:commerce_customer_link, store: store, contact: contact)

    contact.destroy!

    expect(described_class.exists?(link.id)).to be(false)
  end
end
