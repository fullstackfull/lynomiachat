# One operational problem, while it is open (docs/p9/04-operations-center.md).
#
# A signal is a FACT the product observed, never an inference: "this inbox could not authenticate", "this queue
# is over its threshold", "this webhook endpoint refused delivery". There is no anomaly detection and no health
# scoring here, because neither would be a fact.
#
# Two states only. A signal is open until something observes the thing working again, at which point
# `resolved_at` is stamped and the row leaves the open set. Nothing expires a signal on a timer: a problem that
# stopped being reported is not a problem that was fixed, and letting one age out would turn silence into green.
class Operations::Signal < ApplicationRecord
  self.table_name = 'operations_signals'

  enum :severity, { info: 0, warning: 1, critical: 2 }, prefix: :severity

  # Where the observation came from. One entry per writer, so a reader can tell a channel problem from a queue
  # problem without parsing `signal`.
  # `billing` added by P11 (docs/p11/07-security-performance.md): a billing failure is an operations
  # problem an operator must see, and the Operations Center is where they already look. The feed is
  # source-agnostic, so this is one entry rather than a second dashboard.
  # `campaign` added by DECISION 6: a scheduled campaign that could not send is an operations problem with a
  # different subject from a channel's, and a reader must be able to tell them apart without parsing `signal`.
  SOURCES = %w[email_channel whatsapp_channel channel commerce_store webhook queue billing campaign].freeze

  # What was observed. Allow-listed so a typo becomes a validation failure rather than a row nobody will ever
  # find again.
  # P11 adds the three billing signals. This is an allow-list by design, which is why they have to be listed:
  # a signal nobody declared is a signal nobody checked, and the recorder's validation drops it.
  # `feature_disabled` added by DECISION 6: the machine-readable reason a scheduled campaign was not sent.
  SIGNALS = %w[
    authentication_failed connection_failed reauthorization_required
    delivery_failed sync_failed backlog dead_set_grew no_workers
    entitlement_sync_failed unknown_provider_customer billing_event_failed
    feature_disabled
  ].freeze

  # What a signal can be about. An allow-list lists what IS allowed, not what might be, so this is exactly the
  # three subjects the writers use. Channel problems are recorded against the INBOX rather than the channel row,
  # because an inbox is what an operator and a support case both refer to.
  # `Campaign` added by DECISION 6. A blocked campaign is what the operator acts on -- re-activating or
  # cancelling it -- so the campaign is the subject, not its inbox.
  SUBJECT_TYPES = %w[Inbox Commerce::Store Webhook Campaign].freeze

  belongs_to :account, optional: true
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :support_ticket, class_name: 'Support::Ticket', optional: true

  # The incident lifecycle: what happened to this signal, in order, machine events and operator ones together
  # (custom/app/models/operations/signal_event.rb).
  has_many :events, -> { oldest_first }, class_name: 'Operations::SignalEvent',
                                         foreign_key: :operations_signal_id, dependent: :destroy,
                                         inverse_of: :signal

  validates :source, inclusion: { in: SOURCES }
  validates :signal, inclusion: { in: SIGNALS }
  validates :subject_type, inclusion: { in: SUBJECT_TYPES }, allow_nil: true
  validates :reason, length: { maximum: 500 }, allow_nil: true
  validates :first_seen_at, :last_seen_at, presence: true

  scope :open_signals, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :installation_wide, -> { where(account_id: nil) }
  scope :recent_first, -> { order(last_seen_at: :desc, id: :desc) }
  scope :needing_attention, -> { open_signals.where(severity: [:warning, :critical]) }

  # ---- the operator-handling layer (docs/product-refinement/07-operations-control-center-v2.md §2)
  #
  # These describe what an OPERATOR decided, not what the product observed. The two-state rule above is
  # untouched: acknowledging resolves nothing and suppressing hides no fact. Both are only meaningful while the
  # signal is open, which is why every scope here composes with `open_signals`.
  scope :acknowledged, -> { where.not(acknowledged_at: nil) }
  scope :unacknowledged, -> { where(acknowledged_at: nil) }
  # Suppression is time-bounded on purpose, so a lapsed suppression needs no sweep to come back: the predicate
  # itself stops matching the moment the clock passes it.
  scope :suppressed, ->(now = Time.current) { where(suppressed_until: now..) }
  scope :not_suppressed, ->(now = Time.current) { where(suppressed_until: nil).or(where(suppressed_until: ...now)) }

  # The default operator queue: an open problem that matters, that nobody has picked up, and that nobody has
  # deliberately silenced.
  scope :attention_queue, -> { needing_attention.unacknowledged.not_suppressed }

  def open? = resolved_at.nil?
  def acknowledged? = acknowledged_at.present?
  def suppressed?(now = Time.current) = suppressed_until.present? && suppressed_until > now

  # What the queue calls this signal right now. Derived, never stored: a stored status would have to be swept
  # when a suppression lapses, and a sweep that falls behind is how a silenced problem stays silent.
  def handling_state(now = Time.current)
    return 'resolved' unless open?
    return 'suppressed' if suppressed?(now)
    return 'acknowledged' if acknowledged?

    'needs_action'
  end

  # The identity a reader and the support-case bridge both key on. Mirrors the partial unique index.
  def identity
    [account_id.to_i, source, subject_type.to_s, subject_id.to_i, signal]
  end
end
