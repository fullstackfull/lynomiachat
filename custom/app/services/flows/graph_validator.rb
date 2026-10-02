# The server-side check of a flow graph before it is published (docs/flow-builder/04-node-contracts.md §validation). The
# builder's own checks are a convenience; this is the gate.
#
#   shape       nodes / edges arrays, sizes, ids, known node types, positions
#   start       exactly one Start node, nothing leads into it
#   edges       from an existing output of an existing node to an existing node, one edge per output
#   routing     every required output connected (each button / list option included), Go To targets exist
#   reach       every node reachable from Start
#   loops       no cycle that runs without a node that waits (a question, buttons, a list or a delay)
#   nodes       each node's data (Flows::NodeValidator): references of this account only, limits, variables
#   channels    every attached inbox can run every node
#
# Errors are { code, node_id, edge_id, detail } for the builder to show next to the node.
class Flows::GraphValidator
  MAX_NODES = 300
  MAX_EDGES = 900
  MAX_BYTES = 512.kilobytes
  NODE_KEYS = %w[id type position data].freeze
  EDGE_KEYS = %w[id source sourceHandle target].freeze

  def initialize(account, graph, inboxes: [])
    @account = account
    @graph = graph
    @inboxes = inboxes
    @errors = []
  end

  def errors
    return @errors unless shape?

    check_start
    check_edges
    check_routing
    check_reach
    check_loops
    @nodes.each { |node| @errors.concat(Flows::NodeValidator.new(@account, node).errors) }
    check_channels
    @errors
  end

  def valid? = errors.empty?

  # The structure alone (saving a draft): no references, routing or channels.
  def shape_errors
    shape?
    @errors
  end

  private

  def add(code, node_id: nil, edge_id: nil, detail: nil)
    @errors << { code: code, node_id: node_id, edge_id: edge_id, detail: detail }.compact
  end

  def shape?
    return invalid('invalid_graph') unless container?

    code, detail = size_limit
    return invalid(code, detail) if code

    @nodes = @graph['nodes']
    @edges = @graph['edges']
    nodes_shape? && edges_shape?
  end

  def invalid(code, detail = nil)
    add(code, detail: detail)
    false
  end

  def container? = @graph.is_a?(Hash) && @graph['nodes'].is_a?(Array) && @graph['edges'].is_a?(Array)

  def size_limit
    return ['graph_too_large'] if @graph.to_json.bytesize > MAX_BYTES
    return ['too_many_nodes', MAX_NODES] if @graph['nodes'].size > MAX_NODES

    ['too_many_edges', MAX_EDGES] if @graph['edges'].size > MAX_EDGES
  end

  def nodes_shape?
    @nodes.each { |node| check_node_shape(node) }
    ids = @nodes.filter_map { |node| node['id'] if node.is_a?(Hash) }
    add('duplicate_node_id') if ids.uniq.size != ids.size
    @errors.empty?
  end

  def check_node_shape(node)
    return add('invalid_node') unless keyed?(node, NODE_KEYS)
    return add('unknown_node_type', node_id: node['id'], detail: node['type'].to_s.first(40)) unless Flows::NodeTypes.known?(node['type'])

    add('invalid_position', node_id: node['id']) unless position?(node['position'])
  end

  def edges_shape?
    @edges.each { |edge| add('invalid_edge') unless keyed?(edge, EDGE_KEYS) }
    ids = @edges.filter_map { |edge| edge['id'] if edge.is_a?(Hash) }
    add('duplicate_edge_id') if ids.uniq.size != ids.size
    @by_id = @nodes.index_by { |node| node['id'] }
    @errors.empty?
  end

  def keyed?(item, keys) = item.is_a?(Hash) && (item.keys - keys).empty? && Flows::NodeTypes::ID.match?(item['id'].to_s)

  def position?(position)
    position.is_a?(Hash) && %w[x y].all? { |axis| position[axis].is_a?(Numeric) && position[axis].abs < 1_000_000 }
  end

  def check_start
    starts = @nodes.select { |node| node['type'] == 'start' }
    add('start_count', detail: starts.size) unless starts.size == 1
    @start = starts.first
  end

  def check_edges
    seen = {}
    @edges.each do |edge|
      source = @by_id[edge['source']]
      target = @by_id[edge['target']]
      next add('dangling_edge', edge_id: edge['id']) unless source && target
      next add('edge_into_start', edge_id: edge['id']) if target['type'] == 'start'
      next add('unknown_output', node_id: source['id'], edge_id: edge['id']) unless Flows::NodeTypes.outputs(source).include?(edge['sourceHandle'])

      key = [source['id'], edge['sourceHandle']]
      add('duplicate_output', node_id: source['id'], edge_id: edge['id'], detail: edge['sourceHandle']) if seen[key]
      seen[key] = true
    end
  end

  def check_routing
    connected = @edges.to_set { |edge| [edge['source'], edge['sourceHandle']] }
    @nodes.each do |node|
      Flows::NodeTypes.required_outputs(node).each do |output|
        add('unconnected_output', node_id: node['id'], detail: output) unless connected.include?([node['id'], output])
      end
      check_goto(node) if node['type'] == 'goto'
    end
  end

  def check_goto(node)
    target = @by_id[node.dig('data', 'target')]
    add('invalid_target', node_id: node['id']) unless target && target['type'] != 'start' && target['id'] != node['id']
  end

  # Where a node leads: its edges, and a Go To's target.
  def successors(node)
    targets = @edges.select { |edge| edge['source'] == node['id'] }.pluck('target')
    targets << node.dig('data', 'target') if node['type'] == 'goto'
    targets.filter_map { |id| @by_id[id] }
  end

  def check_reach
    return if @start.nil?

    reached = Set[@start['id']]
    queue = [@start]
    while (node = queue.shift)
      successors(node).each { |next_node| queue << next_node if reached.add?(next_node['id']) }
    end
    (@nodes.pluck('id') - reached.to_a).each { |id| add('unreachable', node_id: id) }
  end

  # A cycle among nodes that never wait would run without limit: the runner's step limit would stop it, but such a graph
  # is refused. Cycles through a waiting node (ask again after a wrong answer) are allowed.
  def check_loops
    state = {}
    @nodes.each { |node| add('loop_without_wait', node_id: node['id']) if state[node['id']].nil? && cycle_from?(node, state) }
  end

  def cycle_from?(node, state)
    state[node['id']] = :visiting
    found = !Flows::NodeTypes.waits?(node['type']) && successors(node).any? do |next_node|
      next false if Flows::NodeTypes.waits?(next_node['type'])

      state[next_node['id']] == :visiting || (state[next_node['id']].nil? && cycle_from?(next_node, state))
    end
    state[node['id']] = :done
    found
  end

  def check_channels
    types = @nodes.pluck('type')
    @inboxes.each do |inbox|
      unsupported = Flows::ChannelCapabilities.unsupported(inbox, types)
      add('unsupported_channel', detail: "#{inbox.name}: #{unsupported.join(', ')}") if unsupported.any?
    end
  end
end
