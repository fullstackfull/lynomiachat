# Applies a change to a support case and records what changed (docs/p9/02-support-tickets.md).
#
# Three things happen here that must happen together, which is why they are one service and one transaction:
# the status transition is checked against the allowed table, the SLA clock is paused, resumed or restarted, and
# one history row is written per change. A controller that set attributes directly would get none of it.
class Support::Tickets::Update
  # Each tracked attribute, and the event type its change produces.
  TRACKED = {
    'status' => 'status_changed', 'priority' => 'priority_changed', 'assignee_id' => 'assigned',
    'team_id' => 'team_changed', 'category' => 'category_changed', 'conversation_id' => 'conversation_linked'
  }.freeze

  def initialize(ticket:, user:, attributes:)
    @ticket = ticket
    @user = user
    @attributes = attributes.symbolize_keys
  end

  def perform
    ActiveRecord::Base.transaction do
      previous = @ticket.attributes.slice(*TRACKED.keys).merge('sla_policy_id' => @ticket.sla_policy_id)
      guard_status_transition
      @ticket.assign_attributes(@attributes)
      apply_sla_side_effects(previous)
      apply_lifecycle_timestamps(previous['status'])
      @ticket.last_activity_at = Time.current
      @ticket.save!
      record_changes(previous)
    end

    @ticket
  end

  private

  def guard_status_transition
    return unless @attributes.key?(:status)

    Support::Tickets::StatusTransition.ensure!(@ticket.status, @attributes[:status])
  end

  def clock
    @clock ||= Support::Tickets::SlaClock.new(@ticket)
  end

  # Pause and resume are driven by the status the case is moving INTO, so the rule lives in one place:
  # waiting_on_customer stops the clock, anything else runs it.
  def apply_sla_side_effects(previous)
    clock.apply if @ticket.sla_policy_id.present? && previous['sla_policy_id'].blank?

    return unless @attributes.key?(:status)

    if Support::Ticket::SLA_PAUSING_STATUSES.include?(@ticket.status)
      clock.pause
    else
      clock.resume
      clock.restart_resolution if reopening?(previous['status'])
    end
  end

  def reopening?(previous_status)
    Support::Ticket::TERMINAL_STATUSES.include?(previous_status) && @ticket.active?
  end

  # Entering a terminal state stamps it; reopening clears both. Moving resolved -> closed must NOT clear
  # resolved_at: the case really was resolved at that time, and the pair of timestamps is how "resolved on
  # Monday, closed on Friday" stays readable.
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

  def record_changes(previous)
    recorder = Support::Tickets::EventRecorder.new(ticket: @ticket, user: @user)
    TRACKED.each do |column, event_type|
      before = previous[column]
      after = @ticket[column]
      next if before == after

      recorder.record(event_name(column, event_type, before, after), data: { from: before, to: after })
    end
    record_sla_application(recorder, previous)
  end

  # The three status outcomes an operator actually looks for get their own event names, so the trail reads as a
  # story rather than as six identical `status_changed` rows.
  def event_name(column, event_type, before, after)
    return after.nil? ? 'conversation_unlinked' : 'conversation_linked' if column == 'conversation_id'
    return status_event_name(before, after) if column == 'status'

    event_type
  end

  def status_event_name(before, after)
    return 'reopened' if Support::Ticket::TERMINAL_STATUSES.include?(before.to_s) && @ticket.active?
    return after.to_s if Support::Ticket::TERMINAL_STATUSES.include?(after.to_s)

    'status_changed'
  end

  def record_sla_application(recorder, previous)
    return if @ticket.sla_policy_id.blank? || previous['sla_policy_id'].present?

    recorder.record('sla_applied', data: {
                      sla_policy_id: @ticket.sla_policy_id,
                      first_response_due_at: @ticket.first_response_due_at,
                      resolution_due_at: @ticket.resolution_due_at,
                      business_hours: clock.business_hours_applicable?
                    })
  end
end
