# What a surface may say about a ticket's SLA, and the one object that answers "is anything actually promised".
#
# WHY IT EXISTS. A policy can be attached and still promise nothing on one of the two clocks: M2 requires at
# least ONE threshold, not both, so a resolution-only policy leaves `first_response_due_at` nil. Reading the
# column alone, a renderer cannot tell "no target was set" from "the target is missing", and the honest answer
# matters: the desk must say "No SLA policy applies" rather than display a zero, a dash, or a target it
# invented. That is the same honesty rule the tenant policy enforces with `at_least_one_threshold`.
#
# NO ARITHMETIC AND NO THRESHOLDS HERE. Every answer is read off columns the clock and the sweeper already
# wrote. Nothing in this file knows what a target is worth.
#
# Both surfaces label targets as CALENDAR time, which is why `calendar_time?` is a constant answer in V1
# rather than a policy flag: there is no business-hours path to be in (`PlatformSupport::Sla::Clock`).
class PlatformSupport::Sla::State
  def initialize(ticket)
    @ticket = ticket
  end

  # A policy is attached AND it set at least one target on this ticket. False is the answer the surface turns
  # into "No SLA policy applies".
  def governed?
    @ticket.sla_policy_id.present? && (first_response_promised? || resolution_promised?)
  end

  def first_response_promised?
    @ticket.first_response_due_at.present?
  end

  def resolution_promised?
    @ticket.resolution_due_at.present?
  end

  def first_response_breached?
    @ticket.first_response_breached_at.present?
  end

  def resolution_breached?
    @ticket.resolution_breached_at.present?
  end

  def paused?
    @ticket.sla_paused_at.present?
  end

  def calendar_time?
    true
  end
end
