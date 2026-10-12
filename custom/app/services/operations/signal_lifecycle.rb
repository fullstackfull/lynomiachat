# The only thing that writes an operator's decision about an operational signal
# (docs/product-refinement/07-operations-control-center-v2.md §4).
#
# WHY THIS IS NOT Operations::SignalRecorder
#
# The recorder exists for MACHINE observations: it upserts on the open identity, raises severity monotonically
# and never lowers it, and swallows every error so a validation bug cannot stop email arriving. All three of
# those are wrong for a human action. An operator acknowledging a signal is one deliberate act on one row, it
# must fail loudly if it cannot be recorded, and it must never be silently coalesced with another operator's.
#
# So the two writers stay apart, and the signal's own two states -- open and resolved -- remain the recorder's
# alone. Nothing here resolves a signal, because only an observation may.
#
#   acknowledge  "seen, and I am on it." Removes it from the unacknowledged queue.
#   suppress     "known and noisy; stop ranking it until <time>, because <reason>." Both are REQUIRED.
#   resume       undo either, immediately.
#   record_action a safe corrective action was run against this signal, with its outcome.
#
# EVERY path through this class:
#   * takes an explicit actor and refuses without one -- no ambient `current_user`, for the reason in
#     docs/product-refinement/08-security-performance.md: the `audited` gem's Sweeper resolves the actor through
#     Devise's `:user` scope while a Super Admin is authenticated under `:super_admin`, so an inferred actor
#     here would be nil or wrong;
#   * is idempotent -- acknowledging twice is one acknowledgement, and the second call writes no second event;
#   * writes the incident timeline AND an explicit Custom::AuditLog row with the real actor;
#   * bounds and sanitizes the operator's typed reason, because it is free text that reaches a screen.
#
# It mutates no provider, calls no external service and runs no job. Every method is one UPDATE and two INSERTs.
class Operations::SignalLifecycle
  # The longest an operator may silence a signal in one go. A suppression that outlives the problem is how a
  # real failure stays invisible, so there is no "forever": to keep something quiet, an operator has to come
  # back and say so again.
  MAX_SUPPRESSION = 30.days
  MAX_REASON = Operations::SignalEvent::MAX_REASON

  # Raised when the operator's input cannot be honoured. The caller renders it; it never reaches Sentry.
  class InvalidAction < StandardError; end

  # The safe corrective actions an operator may run and have recorded against a signal. Closed, because an
  # action nobody declared is an action nobody reviewed.
  ACTIONS = %w[health_reprobe commerce_resync].freeze

  def initialize(signal:, actor:)
    raise InvalidAction, 'An operator is required' if actor.nil?

    @signal = signal
    @actor = actor
  end

  # Returns true when this call changed something, false when it was already in that state. The caller uses it
  # to decide what to tell the operator; neither answer is an error.
  def acknowledge(reason: nil)
    return false if @signal.acknowledged?

    apply(acknowledged_at: Time.current, acknowledged_by_id: @actor.id)
    record(Operations::SignalEvent::ACKNOWLEDGED, reason: reason)
    true
  end

  # `until_time` is required and bounded. `reason` is required: a silenced signal with no stated reason is
  # indistinguishable from one somebody muted to make the page look clean.
  def suppress(until_time:, reason:)
    deadline = parse_deadline(until_time)
    text = require_reason(reason)

    apply(suppressed_until: deadline, suppression_reason: text, suppressed_by_id: @actor.id)
    record(Operations::SignalEvent::SUPPRESSED, reason: text,
                                                detail: { 'suppressed_until' => deadline.utc.iso8601 })
    true
  end

  # Clears both layers at once. An operator who resumes monitoring wants the signal back in the queue, and
  # leaving it acknowledged would keep it out of exactly the queue they are asking for it to return to.
  def resume(reason: nil)
    return false unless @signal.acknowledged? || @signal.suppressed_until.present?

    apply(acknowledged_at: nil, acknowledged_by_id: nil,
          suppressed_until: nil, suppression_reason: nil, suppressed_by_id: nil)
    record(Operations::SignalEvent::RESUMED, reason: reason)
    true
  end

  # An operator opened a support case for this signal. Recorded through this class rather than from
  # Operations::CaseBridge so the timeline and the audit keep ONE writer with ONE explicit actor: the bridge
  # knows how to create a case, not who clicked.
  def record_case(ticket)
    record(Operations::SignalEvent::CASE_CREATED, detail: { 'support_ticket_reference' => ticket.reference.to_s })
    true
  end

  # A safe corrective action ran. This records WHAT happened; running it is the action service's business.
  def record_action(action, outcome:, reason: nil)
    raise InvalidAction, "Unknown action #{action}" unless ACTIONS.include?(action.to_s)

    record(Operations::SignalEvent::ACTION_TAKEN, reason: reason,
                                                  detail: { 'action' => action.to_s, 'outcome' => outcome.to_s })
    true
  end

  private

  # One UPDATE under a row lock, so two operators clicking at once cannot interleave into a half-applied state.
  def apply(attributes)
    @signal.with_lock { @signal.update!(attributes) }
  end

  # The timeline row and the audit row, in that order and both required. The audit is NOT best-effort here --
  # unlike Billing::OverrideGrant, where a failed audit must not undo a customer's access -- because nothing
  # depends on an acknowledgement having happened. If it cannot be recorded, it did not happen.
  def record(event_type, reason: nil, detail: {})
    Operations::SignalEvent.create!(
      signal: @signal, event_type: event_type, actor_id: @actor.id, actor_name: actor_name,
      reason: sanitize(reason), detail: detail
    )
    audit(event_type, detail)
  end

  def audit(event_type, detail)
    Custom::AuditLog.create!(
      auditable: @signal, user: @actor, action: 'update',
      comment: "operations.signal.#{event_type}",
      audited_changes: audit_payload(event_type, detail)
    )
  end

  # Ids, enum values, a timestamp and the operator's own reason. The signal's `detail` jsonb is deliberately NOT
  # copied: Operations::SignalRecorder already bounded it on the way in, and re-emitting it here would spread
  # the same values into a second table for no reader's benefit.
  #
  # `associated` is deliberately absent, which files the row installation-wide. An operations signal is
  # Lynomia's own operational record, and `Custom::AuditLog.for_account` serves account-associated rows to that
  # account's own administrators -- so associating it would publish operator activity to the customer.
  def audit_payload(event_type, detail)
    {
      'signal_id' => @signal.id,
      'source' => @signal.source,
      'signal' => @signal.signal,
      'severity' => @signal.severity,
      'subject_account_id' => @signal.account_id,
      'event' => event_type
    }.merge(detail)
  end

  def actor_name
    @actor.try(:available_name).presence || @actor.try(:name).presence || @actor.class.name
  end

  def parse_deadline(value)
    deadline = parse_time(value)
    raise InvalidAction, 'A suppression end time is required' if deadline.nil?
    raise InvalidAction, 'A suppression must end in the future' if deadline <= Time.current
    raise InvalidAction, "A suppression may not exceed #{MAX_SUPPRESSION.inspect}" if deadline > Time.current + MAX_SUPPRESSION

    deadline
  end

  # `Time.zone.parse` answers nil for text that is not a time at all, and RAISES ArgumentError for text that is
  # time-SHAPED with a value out of range -- "2026-13-45T99:99:99" has a thirteenth month. Both are the same
  # mistake from the operator's side, so both get the one controlled answer this surface already gives invalid
  # input. Unhandled, the second one left the controller with an exception, so an operator who mistyped a date
  # got a 500 and Sentry got a report about a typo.
  def parse_time(value)
    return value.to_time if value.is_a?(Time) || value.is_a?(DateTime)

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    raise InvalidAction, 'A suppression end time must be a real date and time'
  end

  def require_reason(value)
    text = sanitize(value)
    raise InvalidAction, 'A reason is required to suppress a signal' if text.blank?

    text
  end

  # Collapsed to one line and truncated, the same treatment Operations::SignalRecorder gives a provider's prose,
  # so an operator cannot paste a wall of text -- or a credential they copied from a log -- into a column a
  # screen renders.
  def sanitize(value)
    return nil if value.blank?

    Operations::SignalRecorder::CREDENTIAL_PATTERNS
      .reduce(value.to_s.gsub(/\s+/, ' ').strip) { |text, (pattern, replacement)| text.gsub(pattern, replacement) }
      .truncate(MAX_REASON)
  end
end
