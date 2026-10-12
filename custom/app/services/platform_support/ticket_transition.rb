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
    ActiveRecord::Base.transaction do
      previous = @ticket.attributes.slice(*TRACKED.keys)
      @ticket.assign_attributes(@attributes)
      apply_lifecycle_timestamps(previous['status'])
      @ticket.last_activity_at = Time.current
      @ticket.save!
      record_changes(previous)
    end

    @ticket
  end

  private

  # Entering a terminal state stamps it. Moving `resolved -> closed` must NOT clear `resolved_at`: the ticket
  # really was resolved then, and the pair of timestamps is how "resolved on Monday, closed on Friday" stays
  # readable. Reopening clears both, because they would otherwise claim a resolution the ticket no longer has.
  def apply_lifecycle_timestamps(previous_status)
    return unless @attributes.key?(:status)

    if reopening?(previous_status)
      @ticket.resolved_at = nil
      @ticket.closed_at = nil
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
