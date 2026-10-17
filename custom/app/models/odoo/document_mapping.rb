# == Schema Information
#
# Table name: odoo_document_mappings
#
# One Stripe money object and the Odoo accounting document it became (docs/odoo/02-architecture.md §5).
#
# THE IDEMPOTENCY RECORD. `idempotency_key` is built by Odoo::SourceStamp and carries the source app, the
# environment, the provider, the kind of document, the provider's own object id and the destination profile.
# Its unique index is the only thing that decides whether a document has already been exported. Not an invoice
# number, not a customer email, not a plan name -- each of those can legitimately repeat across the businesses
# sharing the destination database.
#
# ONE STRIPE INVOICE BECOMES SEVERAL DOCUMENTS over its life: the customer invoice, then the payment, then
# possibly a credit note. They are separate rows with separate keys, which is what keeps registering a payment
# from ever being mistaken for re-creating the invoice.
class Odoo::DocumentMapping < ApplicationRecord
  self.table_name = 'odoo_document_mappings'

  # What we are making in Odoo, and therefore which call sequence applies.
  KINDS = %w[customer_invoice payment credit_note].freeze
  # What the Stripe object is. Kept separate from KINDS because the mapping between them is not one to one: a
  # refund becomes a credit note, and a charge becomes a payment.
  PROVIDER_OBJECT_TYPES = %w[invoice charge refund].freeze

  # Odoo's own state values on account.move, as READ BACK from the server. Recorded for display and never
  # written: `payment_state` in particular is a computed field, and forcing it is how a ledger starts lying
  # about whether it was paid.
  ODOO_STATES = %w[draft posted cancel].freeze

  belongs_to :destination_profile, class_name: 'Odoo::DestinationProfile',
                                   foreign_key: :odoo_destination_profile_id, inverse_of: :document_mappings
  belongs_to :customer_mapping, class_name: 'Odoo::CustomerMapping', optional: true,
                                foreign_key: :odoo_customer_mapping_id, inverse_of: :document_mappings

  enum :state, Odoo::SyncState::STATES, prefix: :state

  validates :provider, :provider_object_id, :source_reference, :idempotency_key, presence: true
  validates :document_kind, inclusion: { in: KINDS }
  validates :provider_object_type, inclusion: { in: PROVIDER_OBJECT_TYPES }
  validates :odoo_state, inclusion: { in: ODOO_STATES }, allow_nil: true
  validates :idempotency_key, uniqueness: true

  scope :unhealthy, -> { where(state: Odoo::SyncState::UNHEALTHY) }
  scope :invoices, -> { where(document_kind: 'customer_invoice') }
  scope :transactions, -> { where(document_kind: %w[payment credit_note]) }
  scope :recent_first, -> { order(occurred_at: :desc, id: :desc) }

  # Returns the row, or nil when this document has already been recorded. The same shape, and the same reason,
  # as BillingWebhookEvent.claim!: the unique index decides the winner, so two workers racing on the same
  # Stripe object cannot both go on to write to Odoo.
  def self.claim!(attributes)
    create!(attributes)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  def exported?
    odoo_record_id.present?
  end

  # Posted means Odoo says posted. Our own `posted_at` is when we asked.
  def posted?
    odoo_state == 'posted'
  end
end
