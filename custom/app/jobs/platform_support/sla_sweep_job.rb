# Runs the Platform Support SLA sweep on a schedule.
#
# Read-mostly and bounded: two partial-index scans and one UPDATE per ticket whose outcome has just been
# decided. It makes no provider call, sends no customer message and touches no conversation.
#
# The schedule entry itself is not added here. `config/schedule.yml` is owned by nobody in this phase's file
# split, so the orchestrator adds the entry -- the job is the unit of work and is callable without it.
class PlatformSupport::SlaSweepJob < ApplicationJob
  queue_as :housekeeping

  def perform
    counts = PlatformSupport::Sla::Sweeper.new.perform
    return if counts.values.sum.zero?

    Lynomia::OperatorLog.info('PLATFORM_SUPPORT_SLA_SWEEP', **counts)
  end
end
