# Applies a status, priority, category or subject change to a Platform Support ticket, and records what changed
# (docs/platform-support/12-refresh-against-product-refinement.md §4, §3 "Audit").
#
# ONE WRITER for all four, because three things have to happen together and a controller assigning attributes
# directly would get none of them: the lifecycle timestamps, one history row per field that actually changed,
# and -- for a staff action -- one audit row with the real operator behind it.
#
# WHO MAY ASK FOR WHAT is NOT decided here. The tenant boundary refuses everything but `priority` and the single
# `resolved -> closed` edge before this service is reached (PlatformSupport::StatusTransition); staff may move a
# ticket to any status. Putting the authority check here as well would be a second answer to the same question.
#
# THE THREE STATUS OUTCOMES AN OPERATOR LOOKS FOR get their own event names -- `resolved`, `closed`, `reopened` --
# so the history reads as a story rather than as six identical `status_changed` rows. All four status event types
# are customer-visible; `priority_changed`, `category_changed` and `subject_changed` are not, because triage is
# internal.
class PlatformSupport::TicketTransition
  # Each field that is tracked, and the event type its change produces.
  TRACKED = { 'status' => 'status_changed', 'priority' => 'priority_changed',
              'category' => 'category_changed', 'subject' => 'subject_changed' }.freeze

  def initialize(ticket:, actor:, attributes:)
    @ticket = ticket
    @actor = actor
    @attributes = attributes.symbolize_keys.slice(:status, :priority, :category, :subject)
  end

  def perform
    previous = nil

    ActiveRecord::Base.transaction do
      # The row is locked before its current values are read, because those values become the `from` half of
      # every history row below. Two operators triaging one ticket at the same moment would otherwise both
      # read the same `from`, and the second would file a history entry describing a state that never existed.
      @ticket.lock!
      previous = @ticket.attributes.slice(*TRACKED.keys)
      @ticket.assign_attributes(@attributes)
      apply_lifecycle_timestamps(previous['status'])
      apply_sla(previous['status'])
      @ticket.last_activity_at = Time.current
      @ticket.save!
      record_changes(previous)
    end

    announce(previous['status'])
    @ticket
  end

  private

  # BOTH HALVES OF THE CLOCK, in the order the tenant desk's own update service uses
  # (custom/app/services/support/tickets/update.rb:46-59), because the two answer different questions:
  #
  #   sync_pause           reads the ticket's CURRENT status, so it is asked after the new status is assigned
  #                        and before the save -- the one ordering that makes `waiting_on_customer` stop the
  #                        clock and every other status resume it, without this service naming either.
  #   restart_resolution   a REOPENED ticket is new work, so its resolution target is measured from now.
  #                        Without this the old target is still in the past, `Sla::Sweeper` matches the row on
  #                        its next pass and records a breach for work that restarted minutes earlier -- a
  #                        permanent false stamp on a routine operator action, with nothing that can undo it.
  def apply_sla(previous_status)
    clock = PlatformSupport::Sla::Clock.new(@ticket)
    clock.sync_pause
    clock.restart_resolution if reopening?(previous_status)
  end

  # Entering a terminal state stamps it. Moving `resolved -> closed` must NOT clear `resolved_at`: the ticket
  # really was resolved then, and the pair of timestamps is how "resolved on Monday, closed on Friday" stays
  # readable. Reopening clears both, because they would otherwise claim a resolution the ticket no longer has.
  def apply_lifecycle_timestamps(previous_status)
    return unless @attributes.key?(:status)

    if reopening?(previous_status)
      @ticket.resolved_at = nil
      @ticket.closed_at = nil
      # The same lifecycle fact `PlatformSupport::MessageCreation` clears on a customer-reply reopen, and for
      # the same reason: a reopened ticket is not a ticket that breached and finished. Cleared here rather
      # than in the clock because a ticket whose policy row has since gone has no clock to ask.
      @ticket.resolution_breached_at = nil
      return
    end

    @ticket.resolved_at ||= Time.current if @ticket.resolved?
    @ticket.closed_at ||= Time.current if @ticket.closed?
  end

  def reopening?(previous_status)
    PlatformSupport::Ticket::CLOSED_STATUSES.include?(previous_status.to_s) &&
      PlatformSupport::Ticket::OPEN_STATUSES.include?(@ticket.status)
  end

  def record_changes(previous)
    recorder = PlatformSupport::EventRecorder.new(ticket: @ticket, actor: @actor)
    TRACKED.each do |field, event_type|
      before = previous[field]
      after = @ticket[field]
      next if before == after

      event = field == 'status' ? status_event_name(before, after) : event_type
      recorder.record(event, metadata: { from: before, to: after })
      audit(event, before, after)
    end
  end

  def status_event_name(before, after)
    return 'reopened' if reopening?(before)
    return after.to_s if PlatformSupport::Ticket::CLOSED_STATUSES.include?(after.to_s)

    'status_changed'
  end

  # THE TWO STATUS CHANGES THAT ASK THE CUSTOMER SOMETHING, and no others. `resolved` says the work is done
  # and invites them to close or come back; `waiting_on_customer` is a question they will not see unless they
  # happen to open the ticket. Every other transition is Lynomia's own bookkeeping, and an email per status
  # change would train the customer to ignore the two that matter.
  #
  # Keyed on the status the ticket now holds rather than on who asked for it: the customer's own vocabulary is
  # `resolved -> closed`, so neither of these is reachable from the tenant surface. After the commit, because
  # a worker can pick up a mail job before the transaction that enqueued it has committed.
  def announce(previous_status)
    return if @ticket.status == previous_status

    PlatformSupport::TicketMailer.ticket_resolved(@ticket).deliver_later if @ticket.resolved?
    PlatformSupport::TicketMailer.waiting_on_customer(@ticket).deliver_later if @ticket.waiting_on_customer?
  end

  # Staff actions only, with the agent's own `User` as the actor so the trail names a person the `users` table
  # knows. A customer changing their own ticket's priority is in the ticket's history, which is where they and
  # the operator both read it.
  def audit(event, before, after)
    return unless @actor.is_a?(PlatformSupport::Agent)

    PlatformSupport::AuditWriter.new(actor: @actor.user).write(
      @ticket, event, { 'from' => before.to_s, 'to' => after.to_s, 'agent_id' => @actor.id }
    )
  end
end
