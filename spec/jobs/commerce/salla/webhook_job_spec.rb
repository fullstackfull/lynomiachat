require 'rails_helper'

# Salla store events (docs/commerce/24-realtime-architecture.md §5): verified like the app events, routed to the realtime
# core for the store of the event's merchant. VERIFY(salla-store-events): the payload shape on a live store.
RSpec.describe Commerce::Salla::WebhookJob do
  include_context 'with commerce encryption'
  include_context 'with salla app'
  include ActiveJob::TestHelper

  let(:store) { create(:commerce_store, :salla, external_store_id: '1234509876') }
  let(:contact) { create(:contact, account: store.account) }
  let!(:link) { create(:commerce_customer_link, store: store, account: store.account, contact: contact, external_customer_id: '1227534533') }
  let(:cache_key) { ->(identifier) { Commerce::Cache.send(:key, store, :orders, identifier) } }
  let(:outdated) { ->(identifier) { JSON.parse(Redis::Alfred.get(cache_key.call(identifier)))['outdated'] == true } }
  let(:seal) { ->(payload) { Commerce::Salla::Webhook.send(:encryptor).encrypt_and_sign(payload.to_json, purpose: :commerce_salla_webhook) } }

  before { %w[1227534533 1227534600].each { |identifier| Redis::Alfred.set(cache_key.call(identifier), '{}') } }

  it "outdates the event customer's cached orders and refreshes its linked contact" do
    event = { event: 'order.updated', merchant: 1_234_509_876, data: { id: 1_861_092_002, customer: { id: 1_227_534_533 } } }
    described_class.perform_now(seal.call(event))

    expect(%w[1227534533 1227534600].map { |identifier| outdated.call(identifier) }).to eq([true, false])
    expect(Commerce::RefreshJob).to have_been_enqueued.with(link.id)
  end

  it "outdates every customer's cached orders for a store event that names no customer" do
    described_class.perform_now(seal.call({ event: 'shipment.updated', merchant: 1_234_509_876, data: { id: 52_000 } }))

    expect(%w[1227534533 1227534600].map { |identifier| outdated.call(identifier) }).to eq([true, true])
    expect(Commerce::RefreshJob).not_to have_been_enqueued
  end

  it 'ignores a store event of a merchant with no connected store' do
    store.update!(status: :disconnected)

    described_class.perform_now(seal.call({ event: 'order.created', merchant: 1_234_509_876, data: { customer: { id: 1_227_534_533 } } }))
    described_class.perform_now(seal.call({ event: 'order.created', merchant: 999, data: { customer: { id: 1_227_534_533 } } }))

    expect(outdated.call('1227534533')).to be(false)
    expect(Commerce::RefreshJob).not_to have_been_enqueued
  end

  it 'still hands app events to the installation flow' do
    installation = instance_double(Commerce::Salla::Installation, process: nil)
    allow(Commerce::Salla::Installation).to receive(:new).and_return(installation)

    described_class.perform_now(seal.call({ event: 'app.uninstalled', merchant: 1_234_509_876, data: {} }))

    expect(installation).to have_received(:process)
    expect(outdated.call('1227534533')).to be(false)
  end
end
