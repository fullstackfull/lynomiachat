require 'rails_helper'

RSpec.describe Commerce::Zid::Webhooks do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, :zid, account: account, external_store_id: '318001') }
  let(:webhooks_url) { 'https://api.zid.sa/v1/managers/webhooks' }
  let(:tokens) { { 'Authorization' => 'Bearer zid-authorization-factory', 'X-Manager-Token' => 'zid-manager-factory' } }
  let(:created) { [] }

  before do
    stub_request(:delete, webhooks_url).with(query: { 'original_id' => '4821' }, headers: tokens).to_return(status: 200, body: '{}')
    stub_request(:post, webhooks_url).with(headers: tokens).to_return do |request|
      created << JSON.parse(request.body)
      { status: 200, body: { id: "wh-#{created.size}", event: created.last['event'], active: true }.to_json }
    end
  end

  it 'subscribes the three order events with a new random Basic Auth pair, after removing the previous subscriptions' do
    described_class.new(store).register

    expect(a_request(:delete, webhooks_url).with(query: { 'original_id' => '4821' })).to have_been_made.once
    expect(created.pluck('event')).to eq(%w[order.create order.status.update order.payment_status.update])
    auth = store.reload.credentials.slice('webhook_username', 'webhook_password')
    expect(auth['webhook_username'].length).to be >= 32
    expect(auth['webhook_password'].length).to be >= 64
    expect(created).to all(include('target_url' => 'https://app.lynomia.test/webhooks/zid/318001', 'original_id' => '4821',
                                   'username' => auth['webhook_username'],
                                   'password' => auth['webhook_password']))
    expect(store.metadata['zid_webhooks']['ids']).to eq(%w[wh-1 wh-2 wh-3])
    expect(store.credentials['authorization']).to eq('zid-authorization-factory')
  end

  it 'never duplicates subscriptions on re-registration, and rotates the credentials' do
    described_class.new(store).register
    first = store.reload.credentials['webhook_password']

    described_class.new(store).register

    expect(a_request(:delete, webhooks_url).with(query: hash_including({}))).to have_been_made.twice
    expect(created.size).to eq(6)
    expect(store.reload.credentials['webhook_password']).not_to eq(first)
  end

  it 'keeps the Basic Auth pair encrypted at rest' do
    described_class.new(store).register

    raw = Commerce::Store.connection.select_value("SELECT credentials FROM commerce_stores WHERE id = #{store.id}")
    expect(raw).not_to include(store.reload.credentials['webhook_password'])
  end

  it 'on disconnect removes the subscriptions, then the tokens, webhook credentials, links and cache; contacts and conversations stay' do
    described_class.new(store).register
    conversation = create(:conversation, account: account)
    create(:commerce_customer_link, store: store, account: account, contact: conversation.contact)
    Redis::Alfred.set("COMMERCE::V1::ACCOUNT::#{account.id}::STORE::#{store.id}::ORDERS::x", '{}')

    Commerce::StoreConnection.new(account: account, user: nil).disconnect(store.reload)

    expect(a_request(:delete, webhooks_url).with(query: hash_including({}))).to have_been_made.twice
    expect(store.reload).to have_attributes(status: 'disconnected', credentials: nil)
    expect(store.customer_links).to be_empty
    expect(Redis::Alfred.get("COMMERCE::V1::ACCOUNT::#{account.id}::STORE::#{store.id}::ORDERS::x")).to be_nil
    expect(conversation.reload.contact).to be_present
  end

  it 'disconnects anyway when Zid cannot be reached to remove the subscriptions' do
    stub_request(:delete, webhooks_url).with(query: hash_including({})).to_return(status: 503)

    Commerce::StoreConnection.new(account: account, user: nil).disconnect(store)

    expect(store.reload).to have_attributes(status: 'disconnected', credentials: nil)
  end
end
