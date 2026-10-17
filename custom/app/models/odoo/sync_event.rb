# == Schema Information
#
# Table name: odoo_sync_events
#
# One queued piece of accounting work (docs/odoo/02-architecture.md §6).
#
# WHY A TABLE RATHER THAN JUST A JOB. A Stripe webhook must answer in milliseconds and must not depend on Odoo
# being reachable, so Billing::WebhookHandler's whole contribution is to insert one of these. Draining it is
# then someone else's problem -- a worker that may fail, be retried, be blocked by a destination that is not
# enabled, or need a human. Those are seven states a Sidekiq job cannot express and an operator cannot read.
#
# `dedup_key` is scoped exactly like a document mapping's idempotency key, so a Stripe redelivery, a second
# webhook about the same object, and a historical import covering a period live sync already handled all
# collapse onto one row instead of producing a second accounting document.
class Odoo::SyncEvent < ApplicationRecord
  self.table_name = 'odoo_sync_events'

  # Where this row came from. The brief requires a historical import to be impossible to confuse with live
  # synchronisation, and this is the column that keeps them apart in every screen and every query.
  ORIGINS = %w[webhook backfill operator].freeze

  MAX_ATTEMPTS = 5
  # Bounded exponential backoff. The ceiling matters more than the curve: an Odoo that has been down for an
  # hour should be retried every few minutes, not once a day, because the operator fixing it needs to see the
  # queue drain while they are still watching.
  BACKOFF = [1.minute, 5.minutes, 20.minutes, 1.hour].freeze
  # A worker that claimed a row and then died leaves `processing` set forever. Nothing else would notice.
  STALE_CLAIM_AFTER = 15.minutes

  belongs_to :destination_profile, class_name: 'Odoo::DestinationProfile',
                                   foreign_key: :odoo_destination_profile_id, inverse_of: :sync_events
  has_many :attempts, -> { order(:attempt_number) }, class_name: 'Odoo::SyncAttempt', dependent: :destroy,
                                                     foreign_key: :odoo_sync_event_id, inverse_of: :sync_event

  enum :state, Odoo::SyncState::STATES, prefix: :state

  validates :provider, :event_type, :provider_object_type, :provider_object_id, :dedup_key, presence: true
  validates :origin, inclusion: { in: ORIGINS }

  scope :unhealthy, -> { where(state: Odoo::SyncState::UNHEALTHY) }
  # A row with no `run_after` has never been attempted; one with a past `run_after` has served its backoff.
  scope :due, ->(now = Time.current) { where(state: [:pending, :retrying]).where('run_after IS NULL OR run_after <= ?', now) }
  scope :stale_claims, ->(now = Time.current) { state_processing.where(claimed_at: ...(now - STALE_CLAIM_AFTER)) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  # Returns the row, or nil when this work is already queued. Same mechanism as BillingWebhookEvent.claim!.
  def self.enqueue(attributes)
    create!(attributes)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  # Called after `attempts_count` has been incremented, so the first failure waits BACKOFF.first and anything
  # past the end of the curve waits its ceiling rather than raising on a nil index.
  def next_run_after(now = Time.current)
    now + BACKOFF[(attempts_count - 1).clamp(0, BACKOFF.length - 1)]
  end

  def attempts_exhausted?
    attempts_count >= MAX_ATTEMPTS
  end
end
