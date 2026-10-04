require 'rails_helper'

RSpec.describe DataImport::ContactRows do
  let(:account) { create(:account) }
  let(:rows) { described_class.new(account, options: options) }
  let(:options) { {} }

  def classify(attributes, number: 1)
    rows.classify(attributes.with_indifferent_access, number: number)
  end

  describe 'phone numbers' do
    it 'normalizes a local number with the row\'s own country' do
      result = classify({ 'phone_number' => '0551112233', 'country_code' => 'SA' })

      expect(result.classification).to eq(:new_contact)
      expect(result.contact.phone_number).to eq('+966551112233')
    end

    it 'normalizes a 00 prefix without needing a country' do
      result = classify({ 'phone_number' => '00966551112233' })

      expect(result.classification).to eq(:new_contact)
      expect(result.contact.phone_number).to eq('+966551112233')
    end

    it 'refuses a local number whose country nothing states, rather than guessing one' do
      result = classify({ 'phone_number' => '0551112233' })

      expect(result.classification).to eq(:invalid)
      expect(result.reason).to eq('phone_country_required')
    end

    it 'keeps a number that already names its country' do
      expect(classify({ 'phone_number' => '+966551112233' }).contact.phone_number).to eq('+966551112233')
    end

    it 'accepts a bare international number the way this importer always has' do
      expect(classify({ 'phone_number' => '918080808080' }).contact.phone_number).to eq('+918080808080')
    end

    it 'names a number that cannot be stored for a reason other than its country' do
      result = classify({ 'phone_number' => '+9', 'country_code' => 'SA' })

      expect(result.classification).to eq(:invalid)
      expect(result.reason).to eq('phone_invalid')
    end

    context 'when the batch chose a country' do
      let(:options) { { default_country: 'SA' } }

      it 'uses it for a row that names none' do
        expect(classify({ 'phone_number' => '0551112233' }).contact.phone_number).to eq('+966551112233')
      end

      it 'still lets the row\'s own country win' do
        result = classify({ 'phone_number' => '05551234567', 'country_code' => 'TR' })

        expect(result.contact.phone_number).to eq('+905551234567')
      end
    end
  end

  describe 'rows that name the same contact' do
    it 'collapses two rows sharing only a phone number onto one contact' do
      first = classify({ 'email' => 'one@example.com', 'phone_number' => '+966551112233' }, number: 1)
      second = classify({ 'email' => 'two@example.com', 'phone_number' => '+966551112233' }, number: 2)

      expect(second.classification).to eq(:duplicate_in_file)
      expect(second.detail).to eq('1')
      expect(second.contact).to be(first.contact)
    end

    it 'collapses two rows sharing an email' do
      classify({ 'email' => 'one@example.com' }, number: 1)

      expect(classify({ 'email' => 'ONE@example.com' }, number: 2).classification).to eq(:duplicate_in_file)
    end
  end

  describe 'a contact the account already has' do
    let!(:existing) { create(:contact, account: account, email: 'existing@example.com', name: 'Old Name') }

    it 'is an update by default, and is not saved by the classifier' do
      result = classify({ 'email' => 'existing@example.com', 'name' => 'New Name' })

      expect(result.classification).to eq(:update_existing)
      expect(result.contact.id).to eq(existing.id)
      expect(existing.reload.name).to eq('Old Name')
    end

    context 'when the batch chose to keep existing details' do
      let(:options) { { duplicate_policy: 'keep' } }

      it 'leaves the row\'s attributes unapplied' do
        result = classify({ 'email' => 'existing@example.com', 'name' => 'New Name' })

        expect(result.classification).to eq(:skip_existing)
        expect(result.contact.name).to eq('Old Name')
      end
    end

    it 'is not found across accounts' do
      other = described_class.new(create(:account))

      expect(other.classify({ 'email' => 'existing@example.com' }.with_indifferent_access, number: 1).classification)
        .to eq(:new_contact)
    end
  end

  describe 'labels' do
    before { create(:label, account: account, title: 'vip') }

    it 'takes the row\'s own labels, trimmed and case-folded' do
      expect(classify({ 'email' => 'a@example.com', 'labels' => ' VIP , vip ' }).labels).to eq(['vip'])
    end

    it 'adds the batch\'s labels to every row' do
      rows = described_class.new(account, options: { labels: ['vip'] })

      expect(rows.classify({ 'email' => 'a@example.com' }.with_indifferent_access, number: 1).labels).to eq(['vip'])
    end

    it 'refuses a label the account does not have, naming it' do
      result = classify({ 'email' => 'a@example.com', 'labels' => 'vip,ghost' })

      expect(result.classification).to eq(:invalid)
      expect(result.reason).to eq('unknown_labels')
      expect(result.detail).to eq('ghost')
    end

    it 'refuses another account\'s label' do
      create(:label, account: create(:account), title: 'elsewhere')

      expect(classify({ 'email' => 'a@example.com', 'labels' => 'elsewhere' }).reason).to eq('unknown_labels')
    end
  end

  describe 'rows with nothing to reach the contact by' do
    it 'is reported as having no identity' do
      result = classify({ 'name' => 'Nameless' })

      expect(result.classification).to eq(:no_identity)
      expect(result.reason).to eq('missing_identity')
    end
  end

  it 'reports whatever the model itself refuses, in the model\'s own words' do
    result = classify({ 'email' => 'not-an-email' })

    expect(result.classification).to eq(:invalid)
    expect(result.reason).to eq('invalid_record')
    expect(result.detail).to include('Email')
  end

  it 'treats a row matching an existing contact by one identity as that contact, not as a new one' do
    existing = create(:contact, account: account, email: 'taken@example.com')
    result = classify({ 'identifier' => 'new-one', 'email' => 'taken@example.com' })

    expect(result.classification).to eq(:update_existing)
    expect(result.contact.id).to eq(existing.id)
    expect(result.contact.identifier).to eq('new-one')
  end
end
