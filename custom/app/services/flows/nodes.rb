# The executor of each node type (docs/flow-builder/04-node-contracts.md).
module Flows::Nodes
  def self.for(run, node) = const_get(node['type'].camelize).new(run, node)
end
