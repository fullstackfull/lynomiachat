# Runs the support SLA sweep on the schedule in config/schedule.yml.
#
# Read-mostly and bounded: two partial-index scans and one UPDATE per case whose outcome has just been decided.
# It writes no provider call, sends no message and touches no conversation.
class Support::SlaSweepJob < ApplicationJob
  queue_as :housekeeping

  def perform
    counts = Support::Tickets::SlaSweeper.new.perform
    return if counts.values.sum.zero?

    Lynomia::OperatorLog.info('SUPPORT_SLA_SWEEP', **counts)
  end
end
