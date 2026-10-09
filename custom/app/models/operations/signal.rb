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
  SOURCES = %w[email_channel whatsapp_channel channel commerce_store webhook queue].freeze

  # What was observed. Allow-listed so a typo becomes a validation failure rather than a row nobody will ever
  # find again.
  SIGNALS = %w[
    authentication_failed connection_failed reauthorization_required
    delivery_failed sync_failed backlog dead_set_grew no_workers
  ].freeze

  # What a signal can be about. An allow-list lists what IS allowed, not what might be, so this is exactly the
  # three subjects the writers use. Channel problems are recorded against the INBOX rather than the channel row,
  # because an inbox is what an operator and a support case both refer to.
  SUBJECT_TYPES = %w[Inbox Commerce::Store Webhook].freeze

  belongs_to :account, optional: true
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :support_ticket, class_name: 'Support::Ticket', optional: true

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

  def open? = resolved_at.nil?

  # The identity a reader and the support-case bridge both key on. Mirrors the partial unique index.
  def identity
    [account_id.to_i, source, subject_type.to_s, subject_id.to_i, signal]
  end
end
