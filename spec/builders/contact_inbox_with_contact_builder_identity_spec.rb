require 'rails_helper'

# The inbound half of unified identity: what happens when a message arrives carrying a number or an address an
# agent has linked to a contact (docs/p10/03-unified-customer-identity.md §5). The OSS matching order lives in
# spec/builders/contact_inbox_with_contact_builder_spec.rb and is untouched.
RSpec.describe ContactInboxWithContactBuilder do
  subject(:contact_inbox) do
    described_class.new(inbox: inbox, source_id: source_id, contact_attributes: contact_attributes).perform
  end

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:customer) { create(:contact, account: account, phone_number: '+96550000001') }
  let(:source_id) { SecureRandom.uuid }
  let(:contact_attributes) { { name: 'Dana', phone_number: '+96560000002' } }

  context 'when the number is linked to an existing contact' do
    before do
      create(:contact_identity, account: account, contact: customer, identity_type: :phone, value: '+96560000002')
    end

    it 'reaches that contact instead of creating another one' do
      expect(contact_inbox.contact_id).to eq(customer.id)
      expect(account.contacts.count).to eq(1)
    end

    it 'still gives the message its own contact inbox for this inbox' do
      expect(contact_inbox.inbox_id).to eq(inbox.id)
      expect(contact_inbox.source_id).to eq(source_id)
    end

    it 'matches through the provider quirks the primary lookup already handles' do
      linked = create(:contact, account: account)
      create(:contact_identity, account: account, contact: linked, identity_type: :phone, value: '+5491112345678')

      result = described_class.new(
        inbox: inbox, source_id: SecureRandom.uuid,
        contact_attributes: { name: 'Dana', phone_number: '+541112345678',
                              phone_number_candidates: ['+5491112345678'] }
      ).perform

      expect(result.contact_id).to eq(linked.id)
    end

    it 'does not reach across accounts' do
      other_account = create(:account)
      other_inbox = create(:inbox, account: other_account)

      result = described_class.new(
        inbox: other_inbox, source_id: SecureRandom.uuid, contact_attributes: contact_attributes
      ).perform

      expect(result.contact_id).not_to eq(customer.id)
      expect(result.contact.account_id).to eq(other_account.id)
    end
  end

  context 'when the address is linked to an existing contact' do
    let(:contact_attributes) { { name: 'Dana', email: 'dana.alt@example.com' } }

    before do
      create(:contact_identity, :email, account: account, contact: customer, value: 'dana.alt@example.com')
    end

    it 'reaches that contact' do
      expect(contact_inbox.contact_id).to eq(customer.id)
    end

    # A provider that reports a mixed-case address must still match: a linked address is stored lower case, so a
    # case-sensitive lookup here would miss it and then try to create a contact holding a value this account has
    # already linked -- which the Contact validation refuses, losing the message.
    it 'reaches that contact whatever case the provider reports' do
      result = described_class.new(
        inbox: inbox, source_id: SecureRandom.uuid,
        contact_attributes: { name: 'Dana', email: 'Dana.Alt@Example.COM' }
      ).perform

      expect(result.contact_id).to eq(customer.id)
    end
  end

  context 'when nothing is linked' do
    it 'creates a contact, exactly as before' do
      expect(contact_inbox.contact_id).not_to eq(customer.id)
      expect(contact_inbox.contact.phone_number).to eq('+96560000002')
    end
  end

  context 'when a primary field and a linked identity both match' do
    # The primary field wins, because the OSS order runs first and this is only its fallback. Stated as a test
    # so the precedence is a decision rather than an accident of ordering.
    it 'prefers the contact whose own phone number it is' do
      owner = create(:contact, account: account, phone_number: '+96560000002')
      create(:contact_identity, account: account, contact: customer, identity_type: :phone, value: '+96599999999')

      expect(contact_inbox.contact_id).to eq(owner.id)
    end
  end
end
