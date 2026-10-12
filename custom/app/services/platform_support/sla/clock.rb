# The Platform Support SLA clock: calendar-time arithmetic over the ticket's own SLA columns.
#
# CALENDAR TIME IN V1, AND THE REASON IS STRUCTURAL. The product's business-hours calculator is inbox-scoped
# from end to end -- `WorkingHours::Config` is set from `inbox.working_hours` and `inbox.timezone`
# (custom/app/services/support/tickets/sla_clock.rb:84-90) and the `working_hours` rows are keyed on an inbox.
# This desk has no inbox, and inventing one to hold a calendar would be fake infrastructure. So `due_at` is
# `from + seconds`, and both surfaces label the target as calendar time. `due_at` is the single seam a later
# installation-level support calendar would replace: one method, one branch (D-7).
#
# TWO CLOCKS, NOT THREE. First response and resolution. The "next response" clock is CUT from V1
# (docs/platform-support/12-refresh-against-product-refinement.md §B-6): the schema contract has no
# `next_response_due_at` and no breach column for it, so the arithmetic could not be recorded and half a clock
# is worse than none. The 75%-of-window warning is cut for the same kind of reason (§B-7): it has no event type
# in the frozen 18-type allow-list, so a warning could not be written down. Neither is reintroduced here.
#
# NO TARGET VALUES LIVE IN THIS FILE, or anywhere else in this module. Thresholds come from the policy record
# and the policy records are owner data. A threshold that is absent or not positive produces NO due time --
# a nil, never a zero -- because a zero would read as "due immediately" and that is a promise nobody made.
#
# MEASURED FROM NOW, NEVER BACKWARDS. `apply` takes `from:` and the caller passes the moment the policy
# attached. A due time invented backwards from an older `created_at` is a commitment nobody made.
#
# MUTATES, DOES NOT SAVE. Every method assigns to the ticket and returns; the caller's transaction saves. That
# is the shape of the tenant clock this copies, and it is what lets a create, a status change and a reopen each
# apply the clock inside the write they were already doing.
#
# WHAT THIS CLOCK DOES NOT DO: it writes no `platform_support_events` row and no audit row. The outcome EVENTS
# are written by whoever decided the outcome -- `PlatformSupport::Sla::Sweeper` for the two breaches it stamps,
# and the operator-reply service for `sla_first_response_met` / `sla_first_response_breached` after it calls
# `#record_first_response` (read `first_response_breached_at` afterwards to pick between the two).
class PlatformSupport::Sla::Clock
  # The one-element list, and the whole pause rule. `waiting_on_customer` pauses; `waiting_on_lynomia` pauses
  # NOTHING, deliberately -- waiting on ourselves is our own delay. Same answer, and same reasoning, as the
  # tenant desk's `SLA_PAUSING_STATUSES` (custom/app/models/support/ticket.rb:37).
  PAUSING_STATUSES = %w[waiting_on_customer].freeze

  def initialize(ticket)
    @ticket = ticket
  end

  # Called when a policy attaches: at creation, or the moment an operator sets one.
  def apply(from: Time.current)
    policy = @ticket.sla_policy
    return if policy.nil?

    @ticket.first_response_due_at = due_at(from, policy.first_response_time_threshold)
    @ticket.resolution_due_at = due_at(from, policy.resolution_time_threshold)
  end

  # A customer reply on a resolved ticket reopens it. The reopened ticket gets a new resolution target from the
  # reopen instant and its resolution breach is cleared, because the new target has its own outcome. A first
  # response that already happened stays satisfied -- `first_responded_at` is not touched here.
  def restart_resolution(from: Time.current)
    policy = @ticket.sla_policy
    return if policy.nil?

    @ticket.resolution_due_at = due_at(from, policy.resolution_time_threshold)
    @ticket.resolution_breached_at = nil
  end

  # THE PAUSE RULE, applied from the ticket's CURRENT status. Call it after a status change has been assigned
  # and before the save. Idempotent in both directions: `pause` returns early when already paused and `resume`
  # returns early when not paused, so a status change between two non-pausing statuses does nothing.
  def sync_pause(at: Time.current)
    PAUSING_STATUSES.include?(@ticket.status.to_s) ? pause(at: at) : resume(at: at)
  end

  def pause(at: Time.current)
    return if @ticket.sla_paused_at.present? || @ticket.sla_policy_id.blank?

    @ticket.sla_paused_at = at
  end

  # Resuming moves every outstanding due time forward by exactly as long as the clock was stopped, and
  # accumulates the total into `sla_paused_seconds` so the pause is VISIBLE rather than inferred from a gap in
  # the timeline. That column is the only thing that makes a resolution-time average honest: without it every
  # average silently includes time spent waiting for the customer.
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

  # The first PUBLIC operator reply decides the first-response outcome, synchronously and once. An internal
  # note does not satisfy this clock and must not reach here. A breach decided at reply time compares message
  # time against due time, never sweep time, so a reply that landed inside the window stays met however late
  # the record is read.
  def record_first_response(at: Time.current)
    return if @ticket.first_responded_at.present?

    @ticket.first_responded_at = at
    due = @ticket.first_response_due_at
    @ticket.first_response_breached_at = at if due.present? && at > due
  end

  private

  # THE SEAM. Calendar time today; an installation-level support calendar would branch here and nowhere else.
  # A blank or non-positive threshold is no promise at all, so the column stays nil and nothing downstream can
  # mistake it for a target of zero.
  def due_at(from, threshold_seconds)
    return nil if threshold_seconds.blank? || threshold_seconds.to_i <= 0

    from + threshold_seconds.to_i.seconds
  end
end
