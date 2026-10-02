require 'rails_helper'

# The publish gate (docs/flow-builder/04-node-contracts.md §validation): structure, routing, reach, loops, references of
# the account only, channel limits, variables.
RSpec.describe Flows::GraphValidator do
  let(:account) { create(:account) }
  let(:other) { create(:account) }
  let(:node) { ->(id, type, data = {}) { { 'id' => id, 'type' => type, 'position' => { 'x' => 0, 'y' => 0 }, 'data' => data } } }
  let(:edge) { ->(source, handle, target) { { 'id' => "#{source}-#{handle}", 'source' => source, 'sourceHandle' => handle, 'target' => target } } }
  let(:codes) { ->(graph) { described_class.new(account, graph).errors.pluck(:code) } }

  it 'accepts a menu flow: buttons routed by option id, a question that loops back, handoff' do
    graph = { 'nodes' => [node.call('s', 'start'),
                          node.call('menu', 'buttons', 'text' => 'How can we help?',
                                                       'options' => [{ 'id' => 'track', 'title' => 'Track order' },
                                                                     { 'id' => 'care', 'title' => 'Customer care' }]),
                          node.call('ask', 'question', 'text' => 'Order number?', 'reply_type' => 'number',
                                                       'store_as' => { 'scope' => 'context', 'key' => 'order_no' }),
                          node.call('again', 'goto', 'target' => 'ask'),
                          node.call('human', 'handoff')],
              'edges' => [edge.call('s', 'next', 'menu'), edge.call('menu', 'track', 'ask'), edge.call('menu', 'care', 'human'),
                          edge.call('ask', 'reply', 'human'), edge.call('ask', 'invalid', 'again')] }

    expect(codes.call(graph)).to eq([])
  end

  it 'refuses structure problems: two starts, unknown types, dangling and duplicate edges, unrouted options, unreachable nodes' do
    graph = { 'nodes' => [node.call('s', 'start'), node.call('s2', 'start'), node.call('x', 'ruby_eval'),
                          node.call('menu', 'buttons', 'text' => 'Pick', 'options' => [{ 'id' => 'a', 'title' => 'A' },
                                                                                       { 'id' => 'b', 'title' => 'B' }]),
                          node.call('e', 'end'), node.call('lost', 'end')],
              'edges' => [edge.call('s', 'next', 'menu'), edge.call('menu', 'a', 'e'), edge.call('menu', 'nope', 'e'),
                          { 'id' => 'dangle', 'source' => 'e', 'sourceHandle' => 'next', 'target' => 'ghost' }] }

    expect(codes.call(graph)).to eq(['unknown_node_type'])
    graph['nodes'].delete_at(2)
    expect(codes.call(graph)).to include('start_count', 'unknown_output', 'dangling_edge', 'unconnected_output', 'unreachable')
  end

  it 'refuses loops that never wait, and allows the ones through a question' do
    graph = { 'nodes' => [node.call('s', 'start'), node.call('a', 'send_message', 'text' => 'a'), node.call('b', 'goto', 'target' => 'a')],
              'edges' => [edge.call('s', 'next', 'a'), edge.call('a', 'next', 'b')] }

    expect(codes.call(graph)).to include('loop_without_wait')
  end

  it 'refuses another account\'s labels, teams, agents, attributes and audiences, unknown variables, and over-long choices' do
    create(:label, account: other, title: 'vip')
    foreign_team = create(:team, account: other)
    foreign_agent = create(:user, account: other)
    audience = create(:custom_filter, account: other, filter_type: :contact, shared: true, user: nil)
    graph = { 'nodes' => [node.call('s', 'start'),
                          node.call('l', 'add_label', 'labels' => ['vip']),
                          node.call('t', 'assign_team', 'team_id' => foreign_team.id),
                          node.call('g', 'assign_agent', 'agent_id' => foreign_agent.id),
                          node.call('c', 'set_contact_attribute', 'key' => 'tier', 'value' => 'gold'),
                          node.call('a', 'audience_condition',
                                    'conditions' => [{ 'attribute_key' => 'contact_audience', 'filter_operator' => 'equal_to',
                                                       'values' => [audience.id], 'query_operator' => nil }]),
                          node.call('m', 'send_message', 'text' => 'Hi {{contact.access_token}} {% if x %}'),
                          node.call('b', 'buttons', 'text' => 'Pick', 'options' => [{ 'id' => 'a', 'title' => 'A title longer than twenty' }]),
                          node.call('h', 'handoff')],
              'edges' => [edge.call('s', 'next', 'l'), edge.call('l', 'next', 't'), edge.call('t', 'next', 'g'), edge.call('g', 'next', 'c'),
                          edge.call('c', 'next', 'a'), edge.call('a', 'true', 'm'), edge.call('a', 'false', 'm'), edge.call('m', 'next', 'b'),
                          edge.call('b', 'a', 'h')] }

    expect(codes.call(graph)).to include('unknown_label', 'unknown_team', 'unknown_agent', 'unknown_attribute', 'invalid_conditions',
                                         'unknown_variable', 'option_title')
  end
end
