# A node executor (docs/flow-builder/04-node-contracts.md). `enter` runs when the session reaches the node; nodes that
# wait also answer `reply(message)` (the customer's next message) and `wake` (their timer).
class Flows::Nodes::Base
  def initialize(run, node)
    @run = run
    @node = node
    @data = node['data'] || {}
  end

  def enter = raise(NotImplementedError)

  # A message the node does not expect: consumed, and the node keeps waiting with its timer.
  def reply(_message) = Flows::Step.wait(wake_at: @run.session.wake_at)

  def wake = Flows::Step.next('timeout')

  private

  def account = @run.account

  def conversation = @run.conversation
end
