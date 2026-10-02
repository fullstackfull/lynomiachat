# The node types of a Lynomia flow graph and their contracts (docs/flow-builder/04-node-contracts.md): the outputs a node
# can be connected from, which of them must be connected, whether it waits, and the shape of its `data`.
#
# An optional output left unconnected hands the conversation to humans when the runner takes it (safe default).
module Flows::NodeTypes
  ID = /\A[A-Za-z0-9_-]{1,64}\z/
  TEXT_MAX = 4096

  TYPES = {
    'start' => { outputs: %w[next], data: %w[keywords conditions] },
    'send_message' => { outputs: %w[next], data: %w[text] },
    'question' => { outputs: %w[reply invalid timeout], optional: %w[invalid timeout], wait: true,
                    data: %w[text reply_type keywords store_as max_attempts retry_text timeout_minutes] },
    'buttons' => { outputs: :options, extra: %w[other timeout], optional: %w[other timeout], wait: true,
                   data: %w[text options timeout_minutes] },
    'list' => { outputs: :options, extra: %w[other timeout], optional: %w[other timeout], wait: true,
                data: %w[text button_label options timeout_minutes] },
    'condition' => { outputs: %w[true false], data: %w[conditions] },
    'audience_condition' => { outputs: %w[true false], data: %w[conditions] },
    'commerce_condition' => { outputs: %w[true false], data: %w[conditions] },
    'set_contact_attribute' => { outputs: %w[next], data: %w[key value] },
    'set_conversation_attribute' => { outputs: %w[next], data: %w[key value] },
    'add_label' => { outputs: %w[next], data: %w[labels] },
    'remove_label' => { outputs: %w[next], data: %w[labels] },
    'assign_agent' => { outputs: %w[next failed], optional: %w[failed], data: %w[agent_id] },
    'assign_team' => { outputs: %w[next failed], optional: %w[failed], data: %w[team_id] },
    'commerce_lookup' => { outputs: %w[found not_found unavailable], optional: %w[not_found unavailable], data: %w[mode] },
    'webhook' => { outputs: %w[next], data: %w[url] },
    'delay' => { outputs: %w[next], wait: true, data: %w[seconds] },
    'handoff' => { outputs: [], data: %w[team_id agent_id priority labels reason] },
    'goto' => { outputs: [], data: %w[target] },
    'end' => { outputs: [], data: %w[resolve] }
  }.freeze

  def self.known?(type) = TYPES.key?(type)

  def self.outputs(node)
    spec = TYPES.fetch(node['type'])
    return spec[:outputs] unless spec[:outputs] == :options

    Array(node.dig('data', 'options')).filter_map { |option| option['id'] if option.is_a?(Hash) } + spec[:extra]
  end

  def self.required_outputs(node) = outputs(node) - Array(TYPES.fetch(node['type'])[:optional])

  def self.waits?(type) = TYPES.dig(type, :wait) == true

  def self.terminal?(type) = TYPES.fetch(type)[:outputs] == []

  def self.data_keys(type) = TYPES.fetch(type)[:data]
end
