require 'rails_helper'

RSpec.describe Commerce::CustomerMatcher do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, account: account, base_url: 'https://shop.example.com', external_store_id: 'shop.example.com') }
  let(:api) { 'https://shop.example.com/wp-json/wc/v3' }
  let(:orders) { JSON.parse(file_fixture('commerce/woocommerce/orders.json').read).index_by { |order| order['id'] } }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:inbox) { whatsapp.inbox }
  let(:source_id) { '966551112233' }
  let(:contact) { create(:contact, account: account, name: 'Omar Khalil', email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: source_id) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:matcher) { described_class.new(store: store, conversation: conversation) }

  before do
    Commerce::Cache.purge(store)
    allow(Resolv).to receive(:getaddresses).with('shop.example.com').and_return(['93.184.216.34'])
    stub_request(:get, "#{api}/orders").with(query: hash_including('search' => '551112233'))
                                       .to_return(status: 200, body: orders.values_at(23, 24, 25).to_json)
    stub_request(:get, "#{api}/orders").with(query: hash_including('search' => '550000111'))
                                       .to_return(status: 200, body: orders.values_at(26, 27).to_json)
  end

  it 'links automatically when the WhatsApp identity phone matches exactly one store customer' do
    result = matcher.call

    expect(result.link).to have_attributes(external_customer_id: 'guest:+966551112233', match_source: 'verified_phone', confirmed_by: nil,
                                           contact: contact, account: account)
  end

  it 'uses an existing link without calling the store' do
    link = create(:commerce_customer_link, store: store, contact: contact, external_customer_id: '2')

    expect(matcher.call.link).to eq(link)
    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it 'offers every customer sharing the verified phone and links none' do
    contact_inbox.update!(source_id: '966550000111')

    result = matcher.call

    expect(result.link).to be_nil
    expect(result.verified.map(&:external_id)).to contain_exactly('3', '4')
    expect(Commerce::CustomerLink.count).to eq(0)
  end

  it 'reads SMS and Twilio identities too' do
    sms = create(:channel_sms, account: account)
    sms_conversation = create(:conversation, account: account, inbox: sms.inbox, contact: contact,
                                             contact_inbox: create(:contact_inbox, contact: contact, inbox: sms.inbox, source_id: '+966551112233'))
    twilio = create(:channel_twilio_sms, account: account, medium: :whatsapp)
    twilio_conversation = create(:conversation, account: account, inbox: twilio.inbox, contact: contact,
                                                contact_inbox: create(:contact_inbox, contact: contact, inbox: twilio.inbox,
                                                                                      source_id: 'whatsapp:+966551112233'))

    expect(described_class.new(store: store, conversation: sms_conversation).trusted_phone).to eq('+966551112233')
    expect(described_class.new(store: store, conversation: twilio_conversation).trusted_phone).to eq('+966551112233')
  end

  it 'has no verified phone for a WhatsApp username identity (BSUID)' do
    contact_inbox.update!(source_id: 'SA.1234567890123456')

    expect(matcher.trusted_phone).to be_nil
  end

  context 'when the conversation has no verified phone (web widget)' do
    let(:inbox) { create(:inbox, account: account) }
    let(:source_id) { SecureRandom.uuid }

    it 'only suggests the customer matching the contact email: agent-editable fields never auto-link' do
      contact.update!(email: 'Omar.Khalil@Example.com')
      stub_request(:get, "#{api}/customers").with(query: hash_including('email' => 'omar.khalil@example.com')).to_return(status: 200, body: '[]')
      stub_request(:get, "#{api}/orders").with(query: hash_including('search' => 'omar.khalil@example.com'))
                                         .to_return(status: 200, body: orders.values_at(23, 24).to_json)

      result = matcher.call

      expect(result.link).to be_nil
      expect(result.suggested.map(&:external_id)).to eq(['guest:omar.khalil@example.com'])
      expect(Commerce::CustomerLink.count).to eq(0)
    end

    it 'only suggests the customer matching a phone number typed on the contact' do
      contact.update!(phone_number: '+966551112233')

      result = matcher.call

      expect([result.link, result.suggested.map(&:external_id)]).to eq([nil, ['guest:+966551112233']])
    end

    it 'finds nothing without an email or phone, and never searches by name' do
      result = matcher.call

      expect([result.link, result.verified, result.suggested]).to eq([nil, [], []])
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end

  it 'caches discovery so reopening the panel does not search the store again' do
    contact_inbox.update!(source_id: '966550000111')
    2.times { described_class.new(store: store, conversation: conversation).call }

    expect(a_request(:get, "#{api}/orders").with(query: hash_including('search' => '550000111'))).to have_been_made.once
  end
end
