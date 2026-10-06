require 'rails_helper'

RSpec.describe Contacts::ViewScope do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  def scope(params)
    described_class.new(account: account, user: user, params: params).perform
  end

  it 'answers the unfiltered list with the contacts the list itself shows' do
    listed = create(:contact, account: account, phone_number: '+966551110001')
    unlisted = create(:contact, account: account)

    expect(scope({})).to include(listed)
    expect(scope({})).not_to include(unlisted)
  end

  it 'answers a label with the contacts carrying it' do
    create(:label, account: account, title: 'vip')
    tagged = create(:contact, account: account, phone_number: '+966551110001')
    tagged.add_labels(['vip'])
    create(:contact, account: account, phone_number: '+966551110002')

    expect(scope({ label: 'vip' })).to contain_exactly(tagged)
  end

  # `identifier` is matched with LIKE where the other three use ILIKE. That asymmetry is the search endpoint's
  # own, carried over here unchanged so that the two agree.
  it 'answers a search over name, email, phone number and identifier' do
    by_name = create(:contact, account: account, name: 'Zuhayr')
    by_email = create(:contact, account: account, email: 'zuhayr@example.com')
    by_phone = create(:contact, account: account, phone_number: '+966551110077')
    by_identifier = create(:contact, account: account, identifier: 'zuhayr-77')
    create(:contact, account: account, name: 'Nobody')

    expect(scope({ q: 'zuhayr' })).to contain_exactly(by_name, by_email, by_identifier)
    expect(scope({ q: '0077' })).to contain_exactly(by_phone)
  end

  it 'answers the online view with whoever is online' do
    online = create(:contact, account: account, phone_number: '+966551110001')
    create(:contact, account: account, phone_number: '+966551110002')
    allow(OnlineStatusTracker).to receive(:get_available_contact_ids).with(account.id).and_return([online.id])

    expect(scope({ active: true })).to contain_exactly(online)
  end

  it 'answers a filter query through the service the filtered list uses' do
    match = create(:contact, account: account, email: 'wholesale@example.com')
    create(:contact, account: account, email: 'retail@example.com')

    result = scope({ payload: [{ 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => 'wholesale',
                                 'query_operator' => nil, 'attribute_model' => 'standard', 'custom_attribute_type' => '' }] })

    expect(result).to contain_exactly(match)
  end

  it 'never leaves the account, whatever the description says' do
    create(:contact, account: create(:account), name: 'Zuhayr', phone_number: '+966551110001')

    expect(scope({ q: 'zuhayr' })).to be_empty
    expect(scope({})).to be_empty
  end

  # A description that names nothing is the unfiltered list, and one that names more than one is answered in the
  # order the page itself picks a view in — never by combining them into a set no page ever showed.
  it 'prefers a search over the filter and the label it was sent with' do
    searched = create(:contact, account: account, name: 'Zuhayr', phone_number: '+966551110001')
    create(:label, account: account, title: 'vip')
    other = create(:contact, account: account, phone_number: '+966551110002')
    other.add_labels(['vip'])

    expect(scope({ q: 'zuhayr', label: 'vip' })).to contain_exactly(searched)
  end

  it 'treats the values a quiet view sends as naming no view at all' do
    listed = create(:contact, account: account, phone_number: '+966551110001')

    expect(scope({ q: '', active: false, payload: [], label: '' })).to contain_exactly(listed)
  end
end
