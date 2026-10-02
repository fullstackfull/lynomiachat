require 'rails_helper'

# Commerce Lookup (docs/flow-builder/04-node-contracts.md §commerce lookup): the contact's own orders only, through
# Customer 360 and the order search, never another customer's order.
RSpec.describe Flows::Nodes::CommerceLookup do
  include_context 'with commerce encryption'

  let(:account) { create(:account).tap { |record| record.enable_features!('lynomia_flow_builder', 'lynomia_commerce') } }
  let(:bot) { create(:agent_bot, account: account, bot_type: :flow, outgoing_url: nil) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:store) { create(:commerce_store, account: account) }
  let(:provider) { Class.new(Commerce::Providers::Base) { def self.searches_orders? = true }.new(store, credentials: {}) }
  let(:order) do
    lambda do |number, customer_id|
      Commerce::Order.new(provider: 'woocommerce', external_order_id: number, order_number: number, status: 'shipped', provider_status: 'completed',
                          payment_status: 'paid', currency: 'SAR', total: '10.00', created_at: '2026-09-30T10:00:00Z', updated_at: nil, items: [],
                          item_count: 0, customer: { external_id: customer_id, name: nil }, shipping: nil, shipments: [],
                          tracking: { number: "TRK#{number}", url: "https://track.example/#{number}" }, admin_order_url: nil, customer_order_url: nil)
    end
  end
  let(:session) do
    FlowSession.create!(account: account, agent_bot: bot, flow_version: Flows::Versions.new(bot).draft, conversation: conversation, status: :active,
                        current_node_id: 'look', context: { 'reply' => '#٩٠٢' })
  end
  let(:lookup) do
    lambda do |data|
      run = Flows::Run.new(session)
      [described_class.new(run, { 'id' => 'look', 'type' => 'commerce_lookup', 'data' => data }).enter.output, run.context['order']]
    end
  end

  before do
    create(:commerce_customer_link, store: store, account: account, contact: contact, external_customer_id: '7')
    allow(Commerce::Providers).to receive(:for).and_return(provider)
    allow(provider).to receive(:list_customer_orders).and_return([order.call('501', '7')])
    Redis::Alfred.delete(format(described_class::THROTTLE_KEY, id: conversation.id))
  end

  it 'finds the contact\'s latest order and exposes its fields to the flow' do
    output, found = lookup.call('mode' => 'latest_order')

    expect(output).to eq('found')
    expect(found).to eq('number' => '501', 'status' => 'shipped', 'payment_status' => 'paid', 'tracking_number' => 'TRK501',
                        'tracking_url' => 'https://track.example/501')
  end

  it 'finds a quoted order number only among the contact\'s own orders' do
    allow(provider).to receive(:find_orders).with('902').and_return([order.call('902', '8')])
    expect(lookup.call('mode' => 'order_number')).to eq(['not_found', nil])

    allow(provider).to receive(:find_orders).with('902').and_return([order.call('902', '8'), order.call('902', '7')])
    expect(lookup.call('mode' => 'order_number')).to match(['found', include('number' => '902', 'tracking_number' => 'TRK902')])
  end

  it 'is unavailable when Commerce is off for the account or the conversation asked too often' do
    expect(lookup.call('mode' => 'latest_order').first).to eq('found')
    (described_class::LOOKUP_LIMIT - 1).times { lookup.call('mode' => 'latest_order') }
    expect(lookup.call('mode' => 'latest_order').first).to eq('unavailable')

    Redis::Alfred.delete(format(described_class::THROTTLE_KEY, id: conversation.id))
    account.disable_features!('lynomia_commerce')
    expect(lookup.call('mode' => 'latest_order').first).to eq('unavailable')
  end
end
