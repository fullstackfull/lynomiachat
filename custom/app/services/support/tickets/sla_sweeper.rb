# Finds the cases whose SLA outcome has been decided and records it once (docs/p9/03-sla-workflow.md).
#
# Two bounded scopes, each backed by its own partial index, so this stays a scheduled read over the working set
# rather than a scan of every case ever opened:
#
#   awaiting_first_response  active, governed, no first response recorded, no first-response breach recorded
#   awaiting_resolution      active, governed, no resolution breach recorded, resolution due time passed
#
# A breach is written once and never un-written: the case really did pass its target, and clearing that later
# would make the history a fiction. Reopening is the one thing that clears a resolution breach, because the
# reopened case has a new target with its own outcome (Support::Tickets::SlaClock#restart_resolution).
#
# Comparison is always MESSAGE TIME against DUE TIME, never sweep time, so a sweep that runs late cannot turn a
# met target into a breach.
class Support::Tickets::SlaSweeper
  BATCH = 500

  def initialize(now: Time.current)
    @now = now
    @counts = { first_response_met: 0, first_response_breached: 0, resolution_breached: 0 }
  end

  def perform
    sweep_first_response
    sweep_resolution
    @counts
  end

  private

  def sweep_first_response
    awaiting_first_response.find_each(batch_size: BATCH) do |ticket|
      responded_at = Support::Tickets::FirstResponseDetector.new(ticket).detect
      if responded_at.present? && responded_at <= ticket.first_response_due_at
        record_first_response(ticket, responded_at)
      elsif responded_at.present?
        record_first_response(ticket, responded_at, breached: true)
      elsif ticket.first_response_due_at < @now && !ticket.sla_paused?
        breach(ticket, :first_response_breached_at, 'sla_first_response_breached')
      end
    end
  end

  def sweep_resolution
    awaiting_resolution.find_each(batch_size: BATCH) do |ticket|
      next if ticket.sla_paused?

      breach(ticket, :resolution_breached_at, 'sla_resolution_breached')
    end
  end

  def awaiting_first_response
    Support::Ticket.active.where.not(sla_policy_id: nil)
                   .where.not(first_response_due_at: nil)
                   .where(first_responded_at: nil, first_response_breached_at: nil)
  end

  def awaiting_resolution
    Support::Ticket.active.where.not(sla_policy_id: nil)
                   .where(resolution_breached_at: nil)
                   .where(resolution_due_at: ...@now)
  end

  def record_first_response(ticket, responded_at, breached: false)
    attributes = { first_responded_at: responded_at }
    attributes[:first_response_breached_at] = responded_at if breached
    ticket.update!(attributes)
    event = breached ? 'sla_first_response_breached' : 'sla_first_response_met'
    Support::Tickets::EventRecorder.new(ticket: ticket).record(event, data: { at: responded_at })
    @counts[breached ? :first_response_breached : :first_response_met] += 1
  end

  def breach(ticket, column, event)
    ticket.update!(column => @now)
    Support::Tickets::EventRecorder.new(ticket: ticket).record(event, data: { due_at: ticket.public_send(
      column == :first_response_breached_at ? :first_response_due_at : :resolution_due_at
    ) })
    @counts[column == :first_response_breached_at ? :first_response_breached : :resolution_breached] += 1
  end
end
