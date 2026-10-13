# Finds the Platform Support tickets whose SLA outcome has been decided against them, and records it once.
#
# TWO BOUNDED SCOPES, EACH SHAPED TO A PARTIAL INDEX the schema contract defines (§1 M3), so this stays a
# scheduled read over the working set rather than a scan of every ticket ever opened:
#
#   awaiting_first_response   partial (first_response_due_at) WHERE first_response_due_at IS NOT NULL
#                             AND first_responded_at IS NULL AND first_response_breached_at IS NULL
#                             AND status < 4
#   awaiting_resolution       partial (resolution_due_at) WHERE resolution_due_at IS NOT NULL
#                             AND resolution_breached_at IS NULL AND status < 4
#
# `status < 4` is why `resolved` and `closed` are numbered last, and `OPEN_STATUSES` is the vocabulary that
# expresses it without this file hard-coding an integer.
#
# IDEMPOTENT BY CONSTRUCTION, not by a guard. Stamping the breach column removes the row from the index
# predicate, so a re-run -- a second sweep, a retried job, two workers -- writes nothing. That is the whole
# reason the breach columns are part of the index condition rather than checked in Ruby.
#
# A BREACH IS WRITTEN ONCE AND NEVER UN-WRITTEN. The ticket really did pass its target. The one thing that
# clears a resolution breach is a reopen, because the reopened ticket has a new target with its own outcome
# (`PlatformSupport::Sla::Clock#restart_resolution`).
#
# A PAUSED TICKET CANNOT BREACH. `waiting_on_customer` stops the clock, so the remaining time is not Lynomia's
# to spend. The filter is `sla_paused_at IS NULL` in SQL rather than a `next if` per row: the index still
# drives the scan and the paused rows never reach Ruby.
#
# MESSAGE TIME AGAINST DUE TIME, NEVER SWEEP TIME, is the rule for a met outcome -- which is why a met first
# response is decided at reply time by the clock and not here. This object only ever decides against the desk.
#
# WHAT IT DOES NOT DO: no audit row (an audit row requires a real operator actor and a sweep has none), no
# notification row (§5 writes exactly one row type and a breach is not it), no provider call, no tenant-visible
# event (every `sla_*` type is excluded from `CUSTOMER_VISIBLE_EVENT_TYPES` -- Lynomia's internal commitments
# are not the customer's business).
class PlatformSupport::Sla::Sweeper
  BATCH = 500

  def initialize(now: Time.current)
    @now = now
    @counts = { first_response_breached: 0, resolution_breached: 0 }
  end

  def perform
    sweep(awaiting_first_response, :first_response_breached_at, 'sla_first_response_breached', :first_response_due_at)
    sweep(awaiting_resolution, :resolution_breached_at, 'sla_resolution_breached', :resolution_due_at)
    @counts
  end

  private

  def sweep(relation, breach_column, event_type, due_column)
    relation.find_each(batch_size: BATCH) do |ticket|
      ticket.update!(breach_column => @now)
      record_event(ticket, event_type, due_at: ticket.public_send(due_column))
      PlatformSupport::TicketMailer.sla_breached(ticket, event_type).deliver_later
      @counts[breach_column == :first_response_breached_at ? :first_response_breached : :resolution_breached] += 1
    end
  end

  # `sla_policy_id IS NOT NULL` is the same question `PlatformSupport::Sla::State#governed?` asks, and it is
  # asked here so the two cannot disagree: the policy foreign key is `on_delete: :nullify`, so deleting a
  # policy row leaves its tickets holding due times with no policy -- and a ticket the desk renders as
  # "No SLA policy applies" must not be breached by a background job nobody can see.
  def awaiting_first_response
    governed.where(first_responded_at: nil, first_response_breached_at: nil)
            .where.not(first_response_due_at: nil)
            .where(first_response_due_at: ...@now)
  end

  def awaiting_resolution
    governed.where(resolution_breached_at: nil)
            .where.not(resolution_due_at: nil)
            .where(resolution_due_at: ...@now)
  end

  def governed
    ::PlatformSupport::Ticket.where(status: ::PlatformSupport::Ticket::OPEN_STATUSES, sla_paused_at: nil)
                             .where.not(sla_policy_id: nil)
  end

  # THE ONE EVENT WRITE IN THIS OBJECT, and the seam to reconcile at integration: if the domain ships a single
  # event recorder, both call sites move to it by changing this method. `metadata` carries two timestamps and
  # nothing else -- no body, no payload, no credential (03-authorization-security.md §11).
  def record_event(ticket, event_type, due_at:)
    ::PlatformSupport::Event.create!(
      platform_support_ticket_id: ticket.id,
      event_type: event_type,
      actor_type: 'System',
      metadata: { 'due_at' => due_at&.iso8601, 'breached_at' => @now.iso8601 }
    )
  end
end
