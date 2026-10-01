require 'rails_helper'

RSpec.describe Commerce::Zid::WebhookJob do
  include_context 'with commerce encryption'
  include_context 'with zid app'
  include ActiveJob::TestHelper

  let(:store) { create(:commerce_store, :zid, external_store_id: '318001') }
  let(:order) { JSON.parse(file_fixture('commerce/zid/orders.json').read)['orders'].first }
  let(:orders_key) { "COMMERCE::V1::ACCOUNT::#{store.account_id}::STORE::#{store.id}::ORDERS" }

  def seal(payload)
    ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key('commerce_zid_webhook', 32))
                                   .encrypt_and_sign(payload.to_json, purpose: :commerce_zid_webhook)
  end

  it "drops the customer's cached orders, and nothing else" do
    Commerce::Cache.fetch(store, :orders, '90001') { [] }
    Commerce::Cache.fetch(store, :orders, '90002') { [] }

    described_class.perform_now(store.id, seal(order))

    expect(Commerce::Cache.fetch(store, :orders, '90001') { ['fresh'] }.value).to eq(['fresh'])
    expect(Commerce::Cache.fetch(store, :orders, '90002') { ['fresh'] }.value).to eq([])
  end

  it 'ignores an event that names another store' do
    Commerce::Cache.fetch(store, :orders, '90001') { [] }

    described_class.perform_now(store.id, seal(order.merge('store_id' => 999)))

    expect(Commerce::Cache.fetch(store, :orders, '90001') { ['fresh'] }.value).to eq([])
  end

  it "refreshes the contact linked to the event's customer, and drops every customer's orders for an event naming none" do
    contact = create(:contact, account: store.account)
    link = create(:commerce_customer_link, store: store, account: store.account, contact: contact, external_customer_id: '90001')
    Commerce::Cache.fetch(store, :orders, '90002') { [] }

    described_class.perform_now(store.id, seal(order))
    expect(Commerce::RefreshJob).to have_been_enqueued.with(link.id)

    described_class.perform_now(store.id, seal(order.except('customer')))
    expect(Commerce::Cache.fetch(store, :orders, '90002') { ['fresh'] }.value).to eq(['fresh'])
  end

  it 'refuses a body that was not sealed by Lynomia' do
    expect { described_class.perform_now(store.id, 'tampered') }.to raise_error(ActiveSupport::MessageEncryptor::InvalidMessage)
  end
end
