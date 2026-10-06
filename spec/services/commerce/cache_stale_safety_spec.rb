require 'rails_helper'

# P6 Stage B (docs/commerce-production/06-cart-transition-design.md §stale): the two stale-cache findings from the
# Stage A gate, pinned.
#
# Commerce::Cache serves an entry up to 24 h old when the store is unavailable, timing out or rate limited. That is
# correct for a display read and wrong for anything durable, so there is one rule:
#
#   STALE CACHE IS NEVER AUTHORITATIVE FOR A PROVIDER WRITE, OR FOR A DURABLE IDENTITY DECISION.
#
# Finding A was real and is fixed here. Finding B — "stale reads may reach a write pre-flight" — turned out NOT to
# exist: every step of the write path calls the provider directly. These examples pin that so it cannot be
# introduced by a later change that reaches for the cache to save a round trip.
RSpec.describe Commerce::Cache do
  include_context 'with commerce encryption'

  let(:account) { create(:account) }
  let(:store) do
    create(:commerce_store, account: account, base_url: 'https://shop.example.com', external_store_id: 'shop.example.com',
                            settings: { 'order_actions' => true })
  end
  let(:api) { 'https://shop.example.com/wp-json/wc/v3' }
  let(:orders) { JSON.parse(file_fixture('commerce/woocommerce/orders.json').read).index_by { |order| order['id'] } }
  let(:whatsapp) { create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false) }
  let(:contact) { create(:contact, account: account, name: 'Omar Khalil', email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: whatsapp.inbox, source_id: '966551112233') }
  let(:conversation) do
    create(:conversation, account: account, inbox: whatsapp.inbox, contact: contact, contact_inbox: contact_inbox)
  end

  before do
    described_class.purge(store)
    allow(Resolv).to receive(:getaddresses).with('shop.example.com').and_return(['93.184.216.34'])
  end

  describe 'finding A — a durable customer link is never created from a stale read' do
    # The real sequence, driven by the clock rather than by reaching into the cache key: one fresh read populates the
    # entry, FRESH_FOR passes, and by the time it is read again the store is unavailable — so Commerce::Cache serves
    # the entry it still holds and marks it stale. The comparison is still exact; the phone-to-customer mapping
    # belongs to the store and may have moved in between.
    def warm!
      stub_request(:get, "#{api}/orders").with(query: hash_including('search' => '551112233'))
                                         .to_return(status: 200, body: orders.values_at(23, 24, 25).to_json)
      Commerce::CustomerMatcher.new(store: store, conversation: conversation).call
      store.customer_links.destroy_all
    end

    # A later stub takes precedence in WebMock, so re-stubbing the same request with a 503 is enough.
    def break_store!
      stub_request(:get, "#{api}/orders").with(query: hash_including('search' => '551112233')).to_return(status: 503, body: '')
    end

    def stale_result
      warm!
      travel(Commerce::Cache::FRESH_FOR + 1.minute) do
        break_store!
        Commerce::CustomerMatcher.new(store: store, conversation: conversation).call
      end
    end

    it 'links from a fresh read' do
      stub_request(:get, "#{api}/orders").with(query: hash_including('search' => '551112233'))
                                         .to_return(status: 200, body: orders.values_at(23, 24, 25).to_json)

      result = Commerce::CustomerMatcher.new(store: store, conversation: conversation).call

      expect(result.stale).to be false
      expect(result.link).to be_present
    end

    it 'declines to link from a stale read, and still offers the match for manual selection' do
      result = stale_result

      expect(result.stale).to be true
      expect(result.verified.size).to eq(1)
      expect(result.link).to be_nil
      expect(store.customer_links.reload).to be_empty
    end

    it 'creates no link even across repeated stale reads' do
      warm!
      travel(Commerce::Cache::FRESH_FOR + 1.minute) do
        break_store!
        3.times { Commerce::CustomerMatcher.new(store: store, conversation: conversation).call }
      end

      expect(store.customer_links.reload).to be_empty
    end

    it 'links once the provider answers again' do
      expect(stale_result.link).to be_nil

      travel(Commerce::Cache::FRESH_FOR + 2.minutes) do
        stub_request(:get, "#{api}/orders").with(query: hash_including('search' => '551112233'))
                                           .to_return(status: 200, body: orders.values_at(23, 24, 25).to_json)

        expect(Commerce::CustomerMatcher.new(store: store, conversation: conversation).call.link).to be_present
      end
    end
  end

  describe 'finding B — no provider-write path consults the cache' do
    # Pinning the invariant rather than a behaviour: these three are every step between an agent asking for an
    # action and the store being written, and none of them may answer from a 24-hour-old entry.
    it 'reads the provider, not the cache, in every write pre-flight step' do
      sources = {
        'Commerce::OrderActions#ensure_owned!' => %w[list_customer_orders],
        'Commerce::OrderActions#owned_snapshot' => %w[action_snapshot],
        'Commerce::ActionExecutor#order_state' => %w[get_order]
      }
      body = File.read(Rails.root.join('custom/app/services/commerce/order_actions.rb')) +
             File.read(Rails.root.join('custom/app/services/commerce/action_executor.rb'))

      sources.each_value { |calls| calls.each { |call| expect(body).to include("provider.#{call}").or include("for(store).#{call}") } }
      expect(body).not_to include('Commerce::Cache.fetch')
    end

    it 'keeps Commerce::Cache.fetch to display reads only' do
      callers = Dir[Rails.root.join('custom/app/**/*.rb')].select { |path| File.read(path).include?('Commerce::Cache.fetch') }
                                                          .map { |path| Pathname.new(path).relative_path_from(Rails.root).to_s }

      expect(callers).to contain_exactly(
        'custom/app/services/commerce/realtime.rb',
        'custom/app/services/commerce/conversation_panel.rb',
        'custom/app/services/commerce/abandoned_carts.rb',
        'custom/app/services/commerce/customer_matcher.rb',
        'custom/app/controllers/api/v1/accounts/commerce/carts_controller.rb'
      )
    end
  end
end
