require 'rails_helper'

# P6 Stage B (docs/commerce-production/06-cart-transition-design.md): the durable Zid cart lifecycle.
#
# Two states and three rules: forward only, provider time only, and no clock creates state. Every example below is
# one of those rules, or one of the identity guarantees the schema rests on.
RSpec.describe Commerce::CartLifecycle do
  include_context 'with commerce encryption'
  include_context 'with zid app'

  let(:account) { create(:account) }
  let(:store) { create(:commerce_store, :zid, account: account) }
  let(:lifecycle) { described_class.new(store) }
  let(:now) { Time.zone.parse('2026-10-06T12:00:00Z') }

  # Zid's documented abandoned-cart shape. `id` is the declared identity; `cart_id` and `session_id` are present
  # precisely because the real payload carries all three and the normalizer must choose one deterministically.
  def zid_cart(overrides = {})
    { 'id' => 'zc-1001', 'cart_id' => 'other-9', 'session_id' => 'sess-7', 'phase' => 'payment_method',
      'created_at' => now.iso8601, 'updated_at' => now.iso8601, 'customer_id' => '55', 'customer_name' => 'Noura',
      'cart_total' => '249.50', 'cart_total_string' => 'SAR 249.50', 'currency_code' => 'SAR', 'products_count' => 3,
      'order_id' => nil, 'url' => 'https://zid-store.zid.store/checkout/abc' }.merge(overrides)
  end

  def created_event(overrides = {})
    delivery('abandoned_cart.created', zid_cart(overrides))
  end

  def completed_event(overrides = {})
    delivery('abandoned_cart.completed', zid_cart({ 'phase' => 'completed', 'order_id' => '7781' }.merge(overrides)))
  end

  def delivery(name, cart)
    Commerce::Providers::Zid::CartEvents.new(cart.merge('event' => name)).event
  end

  # Carts are PRE_UAT for every provider, so the lifecycle ingests nothing until an operator clears the gate. These
  # examples clear it deliberately; the two in `describe 'the gate'` prove it is shut by default.
  around do |example|
    with_modified_env(COMMERCE_ALLOW_PRE_UAT_PROVIDERS: 'true', ZID_RECOVERY_ENABLED: 'true') { example.run }
  end

  describe 'the gate' do
    it 'ingests nothing while the provider is PRE_UAT' do
      result = with_modified_env(COMMERCE_ALLOW_PRE_UAT_PROVIDERS: nil) { lifecycle.apply(created_event) }

      expect(result.reason).to eq('provider_carts_disabled')
      expect(Commerce::Cart.count).to eq(0)
    end

    it 'ingests nothing for a provider whose carts are unsupported' do
      woo = create(:commerce_store, account: account)

      expect(described_class.new(woo).apply(created_event).reason).to eq('provider_carts_disabled')
      expect(Commerce::Cart.count).to eq(0)
    end
  end

  describe 'identity' do
    it 'records one row per store and provider cart id, from the declared identity field' do
      lifecycle.apply(created_event)

      cart = Commerce::Cart.sole
      expect(cart.provider_cart_id).to eq('zc-1001')
      expect(cart).to have_attributes(provider: 'zid', state: 'abandoned', provider_phase: 'payment_method',
                                      currency: 'SAR', item_count: 3, visible_total: 249.5)
    end

    it 'refuses a delivery with no value under the declared identity field rather than inventing one' do
      event = Commerce::Providers::Zid::CartEvents.new(zid_cart.except('id').merge('event' => 'abandoned_cart.created')).event

      expect(event).to be_nil
    end

    it 'keeps two accounts holding the same provider cart id apart' do
      other_store = create(:commerce_store, :zid, account: create(:account))
      lifecycle.apply(created_event)
      described_class.new(other_store).apply(created_event)

      expect(Commerce::Cart.where(provider_cart_id: 'zc-1001').pluck(:commerce_store_id))
        .to contain_exactly(store.id, other_store.id)
      expect(Commerce::Cart.count).to eq(2)
    end

    it 'keeps two stores of one account apart' do
      sibling = create(:commerce_store, :zid, account: account)
      lifecycle.apply(created_event)
      described_class.new(sibling).apply(created_event)

      expect(Commerce::Cart.count).to eq(2)
    end
  end

  describe 'transitions' do
    it 'moves abandoned to completed on the provider completion event' do
      lifecycle.apply(created_event)

      result = lifecycle.apply(completed_event('updated_at' => (now + 10.minutes).iso8601))

      expect(result.transition).to eq('completed')
      expect(Commerce::Cart.sole).to have_attributes(state: 'completed', provider_order_id: '7781',
                                                     completed_at: now + 10.minutes)
    end

    it 'records a completion that arrives before any created event, with the provider abandonment time' do
      result = lifecycle.apply(completed_event('updated_at' => (now + 5.minutes).iso8601))

      expect(result.transition).to eq('completed')
      expect(Commerce::Cart.sole).to have_attributes(state: 'completed', abandoned_at: now)
    end

    it 'never moves a completed cart back to abandoned' do
      lifecycle.apply(completed_event('updated_at' => (now + 5.minutes).iso8601))

      result = lifecycle.apply(created_event('updated_at' => (now + 9.minutes).iso8601))

      expect(result.reason).to eq('state_regression')
      expect(Commerce::Cart.sole.state).to eq('completed')
    end

    it 'ignores an event older than the one already recorded' do
      lifecycle.apply(created_event('updated_at' => (now + 10.minutes).iso8601))

      result = lifecycle.apply(completed_event('updated_at' => (now + 2.minutes).iso8601))

      expect(result.reason).to eq('stale_event')
      expect(Commerce::Cart.sole.state).to eq('abandoned')
    end

    it 'still moves forward when the provider stamps both events identically' do
      lifecycle.apply(created_event)

      result = lifecycle.apply(completed_event('updated_at' => now.iso8601))

      expect(result.transition).to eq('completed')
    end

    it 'treats a duplicate created delivery as no change' do
      lifecycle.apply(created_event)

      result = lifecycle.apply(created_event)

      expect(result.transition).to be_nil
      expect(result.reason).to eq('no_change')
      expect(Commerce::Cart.count).to eq(1)
    end

    it 'treats a duplicate completed delivery as no change' do
      lifecycle.apply(created_event)
      lifecycle.apply(completed_event('updated_at' => (now + 5.minutes).iso8601))

      result = lifecycle.apply(completed_event('updated_at' => (now + 5.minutes).iso8601))

      expect(result.reason).to eq('no_change')
      expect(Commerce::Cart.sole.state).to eq('completed')
    end

    it 'reads completion from the cart state even when the event name says created' do
      event = delivery('abandoned_cart.created', zid_cart('phase' => 'completed', 'order_id' => '7781'))

      expect(lifecycle.apply(event).cart.state).to eq('completed')
    end

    it 'does not write a descriptive field a later sparser delivery omits' do
      lifecycle.apply(created_event)

      lifecycle.apply(delivery('abandoned_cart.completed',
                               { 'id' => 'zc-1001', 'phase' => 'completed', 'updated_at' => (now + 5.minutes).iso8601 }))

      expect(Commerce::Cart.sole).to have_attributes(currency: 'SAR', item_count: 3, state: 'completed')
    end
  end

  describe 'provider outage' do
    # The whole safety argument: abandonment exists only as a provider event, so there is no clock to misfire.
    it 'creates no transition at all when no event arrives' do
      lifecycle.apply(created_event)

      travel 30.days do
        expect { Commerce::Cart.find_each(&:reload) }.not_to(change { Commerce::Cart.sole.state })
      end
    end

    # The structural guarantee, rather than a search for words: the only way in requires an event, and nothing
    # sweeps carts into abandonment on a schedule. So there is no clock that a provider outage could let misfire.
    it 'can only act on a provider event, and nothing sweeps carts into abandonment' do
      expect(described_class.instance_methods(false)).to contain_exactly(:apply)
      expect(described_class.instance_method(:apply).arity).to eq(1)

      # The lifecycle is reachable from exactly one place, and that place is a provider delivery.
      callers = Dir[Rails.root.join('custom/app/**/*.rb')].select { |path| File.read(path).include?('Commerce::CartLifecycle.new(') }
                                                          .map { |path| Pathname.new(path).relative_path_from(Rails.root).to_s }
      expect(callers).to contain_exactly('custom/app/jobs/commerce/zid/webhook_job.rb')

      # And nothing schedules it.
      schedule = Rails.root.join('config/schedule.yml')
      expect(schedule.read).not_to match(/cart/i) if schedule.exist?
    end
  end

  describe 'customer resolution' do
    it 'links the cart to the contact behind the store customer link' do
      contact = create(:contact, account: account)
      link = create(:commerce_customer_link, account: account, store: store, contact: contact, external_customer_id: '55')

      lifecycle.apply(created_event)

      expect(Commerce::Cart.sole).to have_attributes(contact_id: contact.id, commerce_customer_link_id: link.id)
    end

    it 'records a cart whose customer is not linked, with no contact' do
      lifecycle.apply(created_event)

      expect(Commerce::Cart.sole).to have_attributes(contact_id: nil, external_customer_id: '55')
    end
  end

  describe 'what is never stored' do
    it 'keeps the checkout URL and the line items out of the row' do
      lifecycle.apply(created_event)

      stored = Commerce::Cart.sole.attributes.values.map(&:to_s).join(' ')
      expect(stored).not_to include('checkout/abc')
      expect(Commerce::Cart.column_names).not_to include('checkout_url', 'url', 'products', 'payload')
    end
  end
end
