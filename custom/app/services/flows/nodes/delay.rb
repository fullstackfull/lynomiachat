# Delay (docs/flow-builder/04-node-contracts.md §delay): waits `seconds` (at most 24 hours) on a scheduled job, then follows
# `next`. Customer messages during the delay are consumed and do not move the flow; the timer keeps its time.
class Flows::Nodes::Delay < Flows::Nodes::Base
  def enter = Flows::Step.wait(wake_at: Integer(@data['seconds'].to_s).seconds.from_now)

  def wake = Flows::Step.next('next')
end
