# Runs the Platform Support SLA sweep on a schedule.
#
# Read-mostly and bounded: two partial-index scans and one UPDATE per ticket whose outcome has just been
# decided. It makes no provider call, sends no customer message and touches no conversation.
#
# Scheduled every five minutes as `platform_support_sla_sweep_job` in `config/schedule.yml`, beside the tenant
# desk's own sweep. Five minutes is the resolution of a breach timestamp, and nothing reads it sooner.
class PlatformSupport::SlaSweepJob < ApplicationJob
  queue_as :housekeeping

  def perform
    counts = PlatformSupport::Sla::Sweeper.new.perform
    return if counts.values.sum.zero?

    Lynomia::OperatorLog.info('PLATFORM_SUPPORT_SLA_SWEEP', **counts)
  end
end
