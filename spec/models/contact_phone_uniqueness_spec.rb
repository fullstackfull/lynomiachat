require 'rails_helper'

# What the unique index on `(phone_number, account_id)` is for (docs/contacts/11-phone-uniqueness.md §E5).
#
# The model's `uniqueness` validation issues a SELECT, so two requests that both run it before either INSERTs
# both pass it. That is the case these examples put under the constraint; the validation's own behaviour, which
# covers the ordinary sequential one, is in `contact_spec.rb`.
RSpec.describe Contact do
  let(:account) { create(:account) }

  describe 'the database constraint on (phone_number, account_id)' do
    it 'refuses a duplicate the validation did not see' do
      create(:contact, account: account, phone_number: '+966551119001')
      duplicate = build(:contact, account: account, phone_number: '+966551119001')

      # What losing the race amounts to: a record that passed its own validation reaching the INSERT anyway.
      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(account.contacts.where(phone_number: '+966551119001').count).to eq(1)
    end

    it 'leaves the same number in another account alone' do
      create(:contact, account: account, phone_number: '+966551119001')
      elsewhere = build(:contact, account: create(:account), phone_number: '+966551119001')

      expect { elsewhere.save(validate: false) }.not_to raise_error
    end

    # NULLs are distinct from one another in PostgreSQL, which is the whole reason "no number" has to be NULL.
    it 'allows any number of contacts with no number at all' do
      expect { create_list(:contact, 3, account: account) }.to change(account.contacts, :count).by(3)
      expect(account.contacts.where(phone_number: nil).count).to eq(3)
    end

    it 'stores a blank number as no number, so two of them do not collide' do
      first = create(:contact, account: account, phone_number: '')
      second = create(:contact, account: account, phone_number: '')

      expect(first.reload.phone_number).to be_nil
      expect(second.reload.phone_number).to be_nil
    end

    # The same normalization, for the index that has been UNIQUE since the first schema. Before it, the second
    # of these answered 500.
    it 'stores a blank identifier as no identifier' do
      first = create(:contact, account: account, identifier: '')
      second = create(:contact, account: account, identifier: '')

      expect(first.reload.identifier).to be_nil
      expect(second.reload.identifier).to be_nil
    end

    it 'blanks a number cleared by an update, rather than storing an empty string' do
      contact = create(:contact, account: account, phone_number: '+966551119001')

      contact.update!(phone_number: '')

      expect(contact.reload.phone_number).to be_nil
    end
  end
end
