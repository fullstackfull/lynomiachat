# == Schema Information
#
# Table name: commerce_action_runs
#
#  id                   :bigint           not null, primary key
#  action_type          :string           not null
#  completed_at         :datetime
#  error_code           :string
#  idempotency_key      :string           not null
#  metadata             :jsonb            not null
#  provider             :string           not null
#  request_digest       :string           not null
#  started_at           :datetime
#  status               :integer          default("pending"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  commerce_store_id    :bigint
#  contact_id           :bigint
#  conversation_id      :bigint
#  external_resource_id :string           not null
#  provider_request_id  :string
#  requested_by_id      :bigint
#
# Indexes
#
#  index_commerce_action_runs_on_account_id                    (account_id)
#  index_commerce_action_runs_on_contact_id                    (contact_id)
#  index_commerce_action_runs_on_conversation_id               (conversation_id)
#  index_commerce_action_runs_on_idempotency_key               (idempotency_key) UNIQUE
#  index_commerce_action_runs_on_requested_by_id               (requested_by_id)
#  index_commerce_action_runs_on_status_and_updated_at         (status,updated_at)
#  index_commerce_action_runs_on_store_resource_status         (commerce_store_id,external_resource_id,status)
#
# Lynomia Commerce: one order action an agent asked for (refund, cancel, status change, resend), or one recovery message
# an agent prepared for an abandoned cart (`recovery_message`). It is the idempotency record and the audit anchor: a key
# is used once, so a double-click or a replayed request never acts twice.
#
#   pending    accepted, not started (a recovery message: prepared, not sent)
#   running    sent to the store, or the store is still completing it (a Shopify cancellation job)
#   succeeded  the store confirmed it (a recovery message: an agent sent it)
#   failed     the store refused it, or Lynomia stopped before sending it (nothing changed in the store)
#   unknown    sent, but the answer was lost: never sent again, only reconciled by reading the store
#
# `metadata` holds ids, codes and amounts only (the order's version and number, amount, currency, reason, target status,
# refund mode, the order's status afterwards, reconciliation state): never tokens, addresses, customer or order payloads,
# or payment data.
class Commerce::ActionRun < ApplicationRecord
  self.table_name = 'commerce_action_runs'

  ORDER_ACTIONS = %w[update_order_status cancel_order refund_full refund_partial resend_invoice resend_payment_link update_shipping].freeze
  DESTRUCTIVE_ACTIONS = %w[cancel_order refund_full refund_partial].freeze
  RECOVERY_MESSAGE = 'recovery_message'.freeze
  KEY_FORMAT = /\Acommerce-(action|recovery):\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/
  OPEN_STATUSES = %w[pending running unknown].freeze

  belongs_to :account
  belongs_to :store, class_name: 'Commerce::Store', foreign_key: :commerce_store_id, optional: true, inverse_of: false
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :requested_by, class_name: 'User', optional: true

  enum :status, { pending: 0, running: 1, succeeded: 2, failed: 3, unknown: 4 }

  validates :provider, inclusion: { in: Commerce::Store::PROVIDERS }
  validates :action_type, inclusion: { in: ORDER_ACTIONS + [RECOVERY_MESSAGE] }
  validates :external_resource_id, :request_digest, presence: true
  validates :idempotency_key, format: { with: KEY_FORMAT }, uniqueness: true

  scope :order_actions, -> { where(action_type: ORDER_ACTIONS) }
  scope :unresolved, -> { where(status: OPEN_STATUSES) }

  def destructive? = DESTRUCTIVE_ACTIONS.include?(action_type)

  def finished? = succeeded? || failed?

  # Audit entries and metrics: ids, codes and amounts, no customer data.
  def audit_fields
    { provider: provider, store_id: commerce_store_id, order_id: external_resource_id, action: action_type, status: status,
      error_code: error_code, **metadata.slice('amount', 'currency', 'reason', 'target_status').symbolize_keys }.compact
  end

  # What the agent's browser sees: no store ids beyond the store, no provider payload.
  def as_json(*)
    {
      id: id, action_type: action_type, status: status, error_code: error_code, store_id: commerce_store_id,
      order_id: external_resource_id, provider_reference: provider_request_id, created_at: created_at.to_i,
      completed_at: completed_at&.to_i,
      **metadata.slice('order_number', 'amount', 'currency', 'target_status', 'mode', 'result', 'reconcile').symbolize_keys
    }
  end
end
