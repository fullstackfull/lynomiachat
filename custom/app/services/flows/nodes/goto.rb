# Go To (docs/flow-builder/04-node-contracts.md §go to): continues at another node of the flow (Flows::Runner#follow). A
# loop through it must pass a node that waits (Flows::GraphValidator), and the runner's visit limits still apply.
class Flows::Nodes::Goto < Flows::Nodes::Base
  def enter = Flows::Step.next('target')
end
