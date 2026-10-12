# One entry in an operational signal's incident lifecycle
# (docs/product-refinement/07-operations-control-center-v2.md §timeline).
#
# WHAT THIS IS FOR: an operator looking at a recurring problem needs its story in order -- when it was first
# seen, how many times it came back, who acknowledged it, who suppressed it and why, what they did, and when it
# recovered. That is a different question from "who changed product data", which `Custom::AuditLog` answers and
# keeps answering: an operator action writes a row in BOTH, on purpose.
#
# Written only by Operations::SignalLifecycle. The allow-lists below are closed for the same reason
# Operations::SignalRecorder's are: a type nobody declared is a row nobody will look for, and a free-form detail
# hash is how a provider response body ends up on an operator's screen.
class Operations::SignalEvent < ApplicationRecord
  self.table_name = 'operations_signal_events'

  # Machine events -- something the product observed.
  DETECTED = 'detected'.freeze
  RECURRED = 'recurred'.freeze
  RESOLVED = 'resolved'.freeze

  # Operator events -- a human judgement about an open signal.
  ACKNOWLEDGED = 'acknowledged'.freeze
  SUPPRESSED = 'suppressed'.freeze
  RESUMED = 'resumed'.freeze
  ACTION_TAKEN = 'action_taken'.freeze
  CASE_CREATED = 'case_created'.freeze

  EVENT_TYPES = [DETECTED, RECURRED, RESOLVED, ACKNOWLEDGED, SUPPRESSED, RESUMED, ACTION_TAKEN, CASE_CREATED].freeze
  OPERATOR_EVENT_TYPES = [ACKNOWLEDGED, SUPPRESSED, RESUMED, ACTION_TAKEN, CASE_CREATED].freeze

  # Ids, counts, names of safe things and an action's own name. No provider payload, no URL, no credential.
  DETAIL_KEYS = %w[action outcome occurrences previous_status suppressed_until support_ticket_reference].freeze

  MAX_REASON = 500

  belongs_to :signal, class_name: 'Operations::Signal', foreign_key: :operations_signal_id, inverse_of: :events

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :reason, length: { maximum: MAX_REASON }, allow_nil: true

  scope :oldest_first, -> { order(created_at: :asc, id: :asc) }
  scope :by_operator, -> { where(event_type: OPERATOR_EVENT_TYPES) }

  def operator_event? = OPERATOR_EVENT_TYPES.include?(event_type)
end
