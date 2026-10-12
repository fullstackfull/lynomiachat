# frozen_string_literal: true

# One row per billing webhook this installation accepted (docs/p11/04-subscriptions-billing.md).
#
# The unique index on (provider, provider_event_id) IS the idempotency mechanism: `claim!` tries to insert and
# a redelivery loses that insert, so the second attempt is acknowledged rather than processed. That makes it
# safe under concurrency without a lock, because the database decides the winner.
class BillingWebhookEvent < ApplicationRecord
  STATUSES = { received: 0, processed: 1, failed: 2, ignored: 3 }.freeze

  enum status: STATUSES, _prefix: :status

  validates :provider, :provider_event_id, :event_type, presence: true
  validates :provider_event_id, uniqueness: { scope: :provider }

  scope :failures, -> { where(status: :failed) }
  scope :recent_first, -> { order(created_at: :desc) }

  # Returns the new row, or nil when this event has already been seen.
  def self.claim!(provider:, provider_event_id:, event_type:, provider_created_at: nil)
    create!(provider: provider, provider_event_id: provider_event_id,
            event_type: event_type, provider_created_at: provider_created_at)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  def succeeded!(account)
    update!(status: :processed, account_id: account&.id, processed_at: Time.current)
  end

  def ignored!(reason)
    update!(status: :ignored, failure_reason: reason, processed_at: Time.current)
  end

  # Only a classification, never the provider's message: a Stripe error body can quote the request it was
  # given, and this table is read by operators rather than being a place for provider prose.
  def failed!(error)
    update!(status: :failed, failure_reason: error.class.name, processed_at: Time.current)
  end
end
