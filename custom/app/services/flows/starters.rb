# frozen_string_literal: true

# Ready-made flows a merchant can start from, as graphs the server itself can validate.
#
# WHY THESE ARE RUBY AND NOT A CLIENT'S JSON. A template is only worth offering if the graph it
# produces will publish, and whether a graph will publish is Flows::GraphValidator's answer --
# which lives here. A template authored in a client is a graph nobody checked until a merchant
# pressed Publish and was told their starting point was invalid. The spec for this file runs each
# one through the real validator, so "validated template" means validated, not described as such.
#
# NOTHING IN A STARTER NAMES AN ACCOUNT'S OWN RECORDS. No label, team, agent or custom attribute
# appears in any graph below, and that is a constraint rather than an oversight: those are
# validated against the account (`unknown_label`, `unknown_team`, …), so a template naming one
# would be valid for the account it was written against and refused for everybody else. A
# merchant adds their own in the builder, where the picker knows what exists.
#
# `requires` IS REPORTED, NOT ENFORCED HERE. A starter that looks an order up needs Commerce; the
# endpoint says so and the Studio greys it out, and the publish refuses it anyway with
# `commerce_disabled`. One gate, one answer, and a merchant who cannot use a template is told why
# instead of wondering where it went.
module Flows::Starters
  COLUMN = 320
  ROW = 180

  def self.node(id, type, column, row, data = {})
    { 'id' => id, 'type' => type, 'position' => { 'x' => column * COLUMN, 'y' => row * ROW }, 'data' => data }
  end

  def self.edge(source, handle, target)
    { 'id' => "#{source}-#{handle}", 'source' => source, 'sourceHandle' => handle, 'target' => target }
  end

  # A greeting with three choices, each of which ends with a person. The simplest flow that is
  # genuinely useful on its own rather than a demonstration of the editor.
  def self.welcome_menu
    {
      'nodes' => [
        node('start', 'start', 0, 0),
        node('menu', 'buttons', 0, 1,
             { 'text' => 'Hello! How can we help you today?',
               'options' => [{ 'id' => 'order', 'title' => 'My order' },
                             { 'id' => 'product', 'title' => 'A product' },
                             { 'id' => 'other', 'title' => 'Something else' }] }),
        node('order', 'handoff', -1, 2, { 'reason' => 'Asked about an order' }),
        node('product', 'handoff', 0, 2, { 'reason' => 'Asked about a product' }),
        node('other', 'handoff', 1, 2, { 'reason' => 'Asked about something else' })
      ],
      'edges' => [edge('start', 'next', 'menu'), edge('menu', 'order', 'order'),
                  edge('menu', 'product', 'product'), edge('menu', 'other', 'other')]
    }
  end

  # Ask for an order number, look it up, and answer with what the store actually knows. The
  # not-found and unavailable outputs go to a person rather than to an apology.
  def self.order_status
    {
      'nodes' => [
        node('start', 'start', 0, 0, { 'keywords' => %w[order track delivery] }),
        node('ask', 'question', 0, 1,
             { 'text' => 'Sure — what is your order number?', 'reply_type' => 'any', 'max_attempts' => 2,
               'store_as' => { 'scope' => 'context', 'key' => 'order_number' } }),
        node('lookup', 'commerce_lookup', 0, 2, { 'mode' => 'order_number', 'number' => '{{ flow.order_number }}' }),
        node('found', 'send_message', -1, 3,
             { 'text' => 'Order {{ flow.order.number }} is {{ flow.order.status }}. Payment: {{ flow.order.payment_status }}.' }),
        node('done', 'end', -1, 4, { 'resolve' => true }),
        node('missing', 'handoff', 1, 3, { 'reason' => 'Order number not found' })
      ],
      'edges' => [edge('start', 'next', 'ask'), edge('ask', 'reply', 'lookup'),
                  edge('lookup', 'found', 'found'), edge('lookup', 'not_found', 'missing'),
                  edge('lookup', 'unavailable', 'missing'), edge('found', 'next', 'done')]
    }
  end

  # Acknowledge and hand over. For a store that wants automation to do one thing: tell the
  # customer somebody is coming, so the first reply is immediate even when nobody is at a desk.
  def self.acknowledge_and_hand_over
    {
      'nodes' => [
        node('start', 'start', 0, 0),
        node('ack', 'send_message', 0, 1,
             { 'text' => 'Thanks for your message — one of our team will reply shortly.' }),
        node('human', 'handoff', 0, 2, { 'reason' => 'Waiting for a reply' })
      ],
      'edges' => [edge('start', 'next', 'ack'), edge('ack', 'next', 'human')]
    }
  end

  # id, what it needs, and the graph. The NAME and DESCRIPTION are deliberately absent: the words
  # belong to the client, in the merchant's own language, as everywhere else in this contract.
  ALL = [
    { id: 'welcome_menu', requires: [], nodes: 5, graph: welcome_menu },
    { id: 'order_status', requires: ['lynomia_commerce'], nodes: 6, graph: order_status },
    { id: 'acknowledge_and_hand_over', requires: [], nodes: 3, graph: acknowledge_and_hand_over }
  ].freeze

  def self.for(account)
    ALL.map do |starter|
      missing = starter[:requires].reject { |feature| account.feature_enabled?(feature) }
      starter.slice(:id, :requires, :nodes, :graph).merge(available: missing.empty?, missing: missing)
    end
  end
end
