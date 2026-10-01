require 'rails_helper'

# Store events and cached abandoned carts (docs/commerce/30-abandoned-carts.md §realtime): a recovered cart is never shown
# from the cache after an order or cart event, not even as a stale fallback.
RSpec.describe Commerce::Realtime do
  include_context 'with commerce encryption'
  include_context 'with salla app'
  include ActiveJob::TestHelper

  let(:store) { create(:commerce_store, :salla, external_store_id: '1234509876') }
  let(:other_store) { create(:commerce_store, :salla, external_store_id: '1234509877') }
  let!(:link) { create(:commerce_customer_link, store: store, account: store.account, external_customer_id: '1227534533') }
  let(:payload) do
    ->(event) { { 'event' => event, 'merchant' => 1_234_509_876, 'data' => { 'id' => 551_100, 'customer' => { 'id' => 1_227_534_533 } } } }
  end
  let(:cached?) do
    lambda do |target, kind = :carts|
      Redis::Alfred.scan_each(match: "COMMERCE::V1::ACCOUNT::#{target.account_id}::STORE::#{target.id}::#{kind.upcase}::*").any?
    end
  end

  before do
    Redis::Alfred.scan_each(match: 'COMMERCE::*') { |key| Redis::Alfred.delete(key) }
    [store, other_store].each do |target|
      Commerce::Cache.fetch(target, :carts, 'contact:1:') { [{ 'external_cart_id' => '551100', 'status' => 'abandoned' }] }
      Commerce::Cache.fetch(target, :cart_queue, 'recent') { [] }
    end
  end

  it 'drops the store\'s cached carts on a cart event and refreshes the customer\'s linked contacts' do
    expect { described_class.cart_event(store, payload.call('abandoned.cart.update')) }.to have_enqueued_job(Commerce::RefreshJob).with(link.id)

    expect(cached?.call(store)).to be(false)
    expect(cached?.call(store, :cart_queue)).to be(false)
    expect(cached?.call(other_store)).to be(true)
  end

  it 'drops them on an order event too, where an order may have completed the cart' do
    described_class.order_event(store, payload.call('order.created'))

    expect(cached?.call(store)).to be(false)
    expect(cached?.call(other_store)).to be(true)
  end

  it 'routes Salla\'s cart events to it, never as app events' do
    allow(described_class).to receive(:cart_event)
    allow(Commerce::Salla::Installation).to receive(:new)
    allow(Commerce::Salla::Webhook).to receive(:unseal).with('sealed').and_return(payload.call('abandoned.cart'))
    store

    Commerce::Salla::WebhookJob.perform_now('sealed')

    expect(described_class).to have_received(:cart_event).with(store, hash_including('event' => 'abandoned.cart'))
    expect(Commerce::Salla::Installation).not_to have_received(:new)
  end
end
