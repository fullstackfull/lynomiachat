# A node executor (docs/flow-builder/04-node-contracts.md). `enter` runs when the session reaches the node; nodes that
# wait also answer `reply(message)` (the customer's next message) and `wake` (their timer).
class Flows::Nodes::Base
  def initialize(run, node)
    @run = run
    @node = node
    @data = node['data'] || {}
  end

  def enter = raise(NotImplementedError)

  def reply(_message) = Flows::Step.wait

  def wake = Flows::Step.next('timeout')

  private

  def account = @run.account

  def conversation = @run.conversation
end
