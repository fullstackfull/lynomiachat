# One signal's whole story, in order (docs/product-refinement/10-operations-ui.md §timeline).
#
# WHY THE MACHINE EVENTS ARE DERIVED AND NOT STORED. The lifecycle an operator needs to read is: detected,
# recurred, acknowledged, suppressed, resumed, action taken, case opened, recovered. Five of those are
# deliberate human acts and are stored as rows (Operations::SignalEvent, written only by
# Operations::SignalLifecycle). The other three are already columns on the signal itself -- `first_seen_at`,
# `occurrences` with `last_seen_at`, and `resolved_at` -- and storing them again would be strictly worse:
# `recurred` in particular would be one row per observation, so a channel failing every minute would write
# 1,440 timeline rows a day to say the same thing its `occurrences` column already says exactly.
#
# So they are derived here, from those columns, using the same event vocabulary the stored rows use. The
# timeline is complete, the table stays bounded, and there is one place that knows the order.
#
# MACHINE AND HUMAN ARE MARKED, NOT MIXED. `machine` is on every entry, because the distinction is the whole
# point of reading a timeline: "it came back at 03:10" and "somebody suppressed it at 03:12" lead to very
# different next questions.
#
# NOT THE AUDIT LOG. `Custom::AuditLog` answers "who changed product data" and keeps answering it -- every
# operator act writes a row in both, on purpose. This is the operational story of ONE incident, which the audit
# log cannot express, and it never shows a tenant's data.
class Operations::IncidentTimeline
  # `machine` says whether the product observed this or a person did it. `detail` is already bounded on the way
  # in, by the recorder for the signal and by Operations::SignalEvent's own allow-list for the rows.
  Entry = Data.define(:at, :event_type, :actor_name, :reason, :detail, :machine) do
    def machine? = machine
  end

  def initialize(signal, events: nil)
    @signal = signal
    @events = events
  end

  # Oldest first, which is how a story is read. Ties are broken by putting the observation before the human
  # reaction to it: an acknowledgement stamped in the same second as a recurrence happened after it.
  def call
    (observations + operator_entries).sort_by.with_index { |entry, index| [entry.at, entry.machine? ? 0 : 1, index] }
  end

  private

  def observations
    entries = [entry(@signal.first_seen_at, Operations::SignalEvent::DETECTED, detail: detection_detail)]
    entries << recurrence if recurred?
    entries << recovery if @signal.resolved_at.present?
    entries
  end

  def recovery
    entry(@signal.resolved_at, Operations::SignalEvent::RESOLVED, reason: 'The product observed this working again')
  end

  # The signal's `reason` belongs to detection: it is what the observation said at the time, already bounded and
  # redacted by Operations::SignalRecorder.
  def detection_detail
    { 'source' => @signal.source, 'severity' => @signal.severity }
  end

  # ONE entry for every recurrence, carrying the count. Not one per occurrence: the table would grow without
  # limit and the operator would learn nothing the count does not already tell them.
  def recurrence
    entry(@signal.last_seen_at, Operations::SignalEvent::RECURRED,
          reason: "Observed #{@signal.occurrences} times in total",
          detail: { 'occurrences' => @signal.occurrences })
  end

  def recurred?
    @signal.occurrences.to_i > 1 && @signal.last_seen_at.present? && @signal.last_seen_at != @signal.first_seen_at
  end

  def operator_entries
    events.map do |event|
      Entry.new(at: event.created_at, event_type: event.event_type, actor_name: event.actor_name,
                reason: event.reason, detail: event.detail || {}, machine: !event.operator_event?)
    end
  end

  def events = @events || @signal.events.to_a

  def entry(at, event_type, reason: nil, detail: {})
    Entry.new(at: at, event_type: event_type, actor_name: nil, reason: reason || @signal.reason, detail: detail, machine: true)
  end
end
