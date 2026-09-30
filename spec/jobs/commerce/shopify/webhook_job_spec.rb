require 'rails_helper'

RSpec.describe Commerce::Shopify::WebhookJob do
  include_context 'with commerce encryption'
  include_context 'with shopify commerce app'

  let(:account) { create(:account) }
  let(:store) do
    create(:commerce_store, :shopify, account: account, external_store_id: '68210001', base_url: 'https://lynomia-demo.myshopify.com',
                                      metadata: { 'verified_at' => '2026-09-01T00:00:00Z' })
  end
  let(:shop) { 'lynomia-demo.myshopify.com' }
  let(:triggered_at) { '2026-09-30T10:00:00.123456789Z' }
  let(:sara) { create(:contact, account: account, email: 'sara.ali@example.com') }
  let(:guest) { create(:contact, account: account, email: 'guest.buyer@example.com') }
  let(:other) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: sara) }
  let(:customer) { { 'id' => 7001, 'email' => 'Sara.Ali@example.com', 'phone' => '+966551112233' } }
  let(:seal) do
    ->(payload) { Commerce::WebhookQueue.send(:encryptor, 'shopify').encrypt_and_sign(payload.to_json, purpose: 'commerce_shopify_webhook') }
  end
  let(:cache_key) { ->(identifier) { Commerce::Cache.send(:key, store, :orders, identifier) } }

  before do
    create(:commerce_customer_link, store: store, account: account, contact: sara, external_customer_id: '7001')
    create(:commerce_customer_link, store: store, account: account, contact: guest, external_customer_id: 'guest:sara.ali@example.com')
    create(:commerce_customer_link, store: store, account: account, contact: other, external_customer_id: '7002')
    %w[7001 7002 guest:guest.buyer@example.com].each { |identifier| Redis::Alfred.set(cache_key.call(identifier), '{}') }
  end

  def run(topic, payload)
    described_class.perform_now(topic, shop, triggered_at, seal.call(payload))
  end

  it "drops only the customer's cached orders on an order event" do
    run('orders/updated', { 'id' => 6_001_006, 'email' => 'sara.ali@example.com', 'customer' => customer })

    expect(Redis::Alfred.exists?(cache_key.call('7001'))).to be(false)
    expect(Redis::Alfred.exists?(cache_key.call('7002'))).to be(true)
  end

  it "drops a guest's cached orders on a guest checkout event" do
    run('orders/create', { 'id' => 6_001_010, 'email' => 'Guest.Buyer@Example.com', 'customer' => nil })

    expect(Redis::Alfred.exists?(cache_key.call('guest:guest.buyer@example.com'))).to be(false)
    expect(Redis::Alfred.exists?(cache_key.call('7001'))).to be(true)
  end

  it 'disconnects the store on app/uninstalled, removing its token, links and cache, and keeping contacts and conversations' do
    conversation

    run('app/uninstalled', { 'id' => 68_210_001, 'myshopify_domain' => shop })

    expect(store.reload).to have_attributes(status: 'disconnected', credentials: nil)
    expect(store.customer_links).to be_empty
    expect(Redis::Alfred.exists?(cache_key.call('7002'))).to be(false)
    expect([sara, guest, other].map { |contact| Contact.exists?(contact.id) }).to all(be(true))
    expect(Conversation.exists?(conversation.id)).to be(true)
    expect(Enterprise::AuditLog.where(auditable: store).pluck(:comment)).to include('commerce.shopify.uninstalled') if defined?(Enterprise::AuditLog)
  end

  it 'ignores an uninstall whose signed body names another shop, or that is older than the current authorization' do
    run('app/uninstalled', { 'id' => 5, 'myshopify_domain' => shop })
    expect(store.reload).to be_active

    store.update!(metadata: { 'verified_at' => '2026-09-30T11:00:00Z' })
    run('app/uninstalled', { 'id' => 68_210_001, 'myshopify_domain' => shop })
    expect(store.reload).to be_active
  end

  it "removes the redacted customer's links, registered and guest, and the store cache; the audit keeps counts only" do
    run('customers/redact', { 'shop_id' => 68_210_001, 'shop_domain' => shop, 'customer' => customer, 'orders_to_redact' => [6_001_006] })

    expect(store.customer_links.pluck(:external_customer_id)).to eq(['7002'])
    expect(Redis::Alfred.exists?(cache_key.call('7002'))).to be(false)
    expect([sara, guest].map { |contact| Contact.exists?(contact.id) }).to all(be(true))
    if defined?(Enterprise::AuditLog)
      audit = Enterprise::AuditLog.find_by!(comment: 'commerce.shopify.customer_redacted')
      expect(audit.audited_changes).to eq('customer_links_removed' => 2)
      expect(audit.to_json).not_to include('sara.ali', '966551112233', '7001')
    end
  end

  it 'records a customer data request for the operator, with the link ids to export and no personal data, removing nothing' do
    run('customers/data_request', { 'shop_id' => 68_210_001, 'shop_domain' => shop, 'customer' => customer, 'data_request' => { 'id' => 9999 } })

    expect(store.customer_links.count).to eq(3)
    if defined?(Enterprise::AuditLog)
      audit = Enterprise::AuditLog.find_by!(comment: 'commerce.shopify.customer_data_requested')
      expect(audit.audited_changes).to eq('customer_link_ids' => store.customer_links.where(contact: [sara, guest]).order(:id).pluck(:id),
                                          'data_request_id' => 9999)
      expect(audit.to_json).not_to include('sara.ali', '966551112233')
    end
  end

  it 'deletes the store, its links and cache on shop/redact, keeping contacts, conversations and a minimal audit' do
    conversation

    run('shop/redact', { 'shop_id' => 68_210_001, 'shop_domain' => shop })

    expect(Commerce::Store.exists?(store.id)).to be(false)
    expect(Commerce::CustomerLink.where(commerce_store_id: store.id)).to be_empty
    expect(Redis::Alfred.exists?(cache_key.call('7001'))).to be(false)
    expect(Conversation.exists?(conversation.id)).to be(true)
    expect(Contact.where(id: [sara.id, guest.id, other.id]).count).to eq(3)
    if defined?(Enterprise::AuditLog)
      audit = Enterprise::AuditLog.find_by!(comment: 'commerce.shopify.shop_redacted')
      expect(audit).to have_attributes(auditable: account)
      expect(audit.audited_changes).to eq('store_id' => store.id, 'customer_links_removed' => 3)
    end
  end

  it 'applies the privacy topics only to the shop named in the signed body' do
    run('customers/redact', { 'shop_id' => 5, 'shop_domain' => shop, 'customer' => customer })
    run('shop/redact', { 'shop_id' => 5, 'shop_domain' => shop })

    expect(store.reload.customer_links.count).to eq(3)
  end

  it 'touches nothing of a shop that is not connected, or of the legacy integration' do
    hook = create(:integrations_hook, :shopify, account: account, reference_id: 'legacy-only.myshopify.com')

    described_class.perform_now('app/uninstalled', 'legacy-only.myshopify.com', triggered_at, seal.call({ 'id' => 1 }))
    described_class.perform_now('shop/redact', 'legacy-only.myshopify.com', triggered_at, seal.call({ 'shop_id' => 1 }))

    expect(Integrations::Hook.exists?(hook.id)).to be(true)
    expect(store.reload).to be_active
  end

  it 'refuses a body that was not sealed by Lynomia' do
    expect { described_class.perform_now('shop/redact', shop, triggered_at, 'tampered') }
      .to raise_error(ActiveSupport::MessageEncryptor::InvalidMessage)
  end
end
