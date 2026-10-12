# The support-case SLA clock (docs/p9/03-sla-workflow.md).
#
# There is no SLA engine in this fork to reuse: Chatwoot's lived in enterprise/, which is permanently absent.
# What IS reusable, and is reused here, is the business-hours calculator -- ReportingEventHelper plus the
# `working_hours` gem (app/helpers/reporting_event_helper.rb, Gemfile:166) -- the WorkingHour rows an inbox
# already has, and the sla_policies table the OSS schema already ships.
#
# Business hours are inbox-scoped, because that is the scope the gem configuration has: WorkingHours::Config is
# set from inbox.working_hours and inbox.timezone. A case with no inbox therefore uses calendar time even under a
# business-hours policy, and the API says so rather than quietly pretending otherwise.
class Support::Tickets::SlaClock
  include ReportingEventHelper

  def initialize(ticket)
    @ticket = ticket
  end

  # Called when a policy is attached: at create if one was given, otherwise the moment it is set. The targets are
  # measured from NOW and never retroactively from an older created_at, because a due time invented backwards is
  # a commitment nobody made.
  def apply(from: Time.current)
    policy = @ticket.sla_policy
    return if policy.nil?

    @ticket.first_response_due_at = due_at(from, policy.first_response_time_threshold, policy)
    @ticket.resolution_due_at = due_at(from, policy.resolution_time_threshold, policy)
  end

  # A new resolution target from the reopen instant. A first response that already happened stays satisfied, and
  # a resolution breach is cleared because the new target has its own outcome.
  def restart_resolution(from: Time.current)
    policy = @ticket.sla_policy
    return if policy.nil?

    @ticket.resolution_due_at = due_at(from, policy.resolution_time_threshold, policy)
    @ticket.resolution_breached_at = nil
  end

  def pause(at: Time.current)
    return if @ticket.sla_paused_at.present? || @ticket.sla_policy_id.blank?

    @ticket.sla_paused_at = at
  end

  # Resuming moves both due times forward by exactly as long as the clock was stopped, and records the total so
  # the pause is visible rather than inferred from a gap.
  def resume(at: Time.current)
    paused_at = @ticket.sla_paused_at
    return if paused_at.blank?

    seconds = (at - paused_at).round
    seconds = 0 if seconds.negative?
    @ticket.sla_paused_seconds = @ticket.sla_paused_seconds.to_i + seconds
    @ticket.first_response_due_at += seconds if @ticket.first_response_due_at.present?
    @ticket.resolution_due_at += seconds if @ticket.resolution_due_at.present?
    @ticket.sla_paused_at = nil
  end

  # Whether the policy's business-hours switch can actually be honoured for this case.
  def business_hours_applicable?
    policy = @ticket.sla_policy
    return false if policy.nil? || !policy.only_during_business_hours?

    inbox = @ticket.inbox
    inbox.present? && inbox.working_hours_enabled?
  end

  private

  def due_at(from, threshold_seconds, policy)
    return nil if threshold_seconds.blank? || threshold_seconds.to_f <= 0

    seconds = threshold_seconds.to_f
    return from + seconds.seconds unless business_hours_applicable?

    business_hours_due_at(from, seconds, policy)
  end

  # `configure_working_hours` is ReportingEventHelper's own private method; including the helper makes it
  # available here, so the day map and the "closed all day" handling are not written a second time.
  def business_hours_due_at(from, seconds, _policy)
    inbox = @ticket.inbox
    hours = configure_working_hours(inbox.working_hours)
    return from + seconds.seconds if hours.blank?

    WorkingHours::Config.working_hours = hours
    WorkingHours::Config.time_zone = inbox.timezone
    # `working` is defined on Integer by the gem, and a threshold column is a float.
    (from.in_time_zone(inbox.timezone).to_time + seconds.round.working.seconds).utc
  end
end
