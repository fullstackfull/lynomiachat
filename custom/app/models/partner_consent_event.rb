# One decision a partner reported, applied or not
# (docs/partner-consent/ADR-001-partner-scoped-consent.md).
#
# APPEND-ONLY, AND KEPT EVEN WHEN IT CHANGED NOTHING. An event that was ignored as a duplicate,
# superseded by a newer one, or refused because the customer had withdrawn is exactly what a
# reconciliation run and an audit need to see: without it, "the partner never sent it" and
# "the partner sent it and we correctly ignored it" look identical. `outcome` says which.
#
# THE id IS THE ORDERING KEY. It is assigned by Postgres at insert, so it is server-controlled
# and monotonic in assignment order; `captured_at` is the partner's claim about when the
# customer acted and is evidence rather than an order. See Partners::Consents.
class PartnerConsentEvent < ApplicationRecord
  belongs_to :platform_app
  belongs_to :account
  belongs_to :commerce_store, class_name: 'Commerce::Store'
  belongs_to :contact
  belongs_to :recorded_by, class_name: 'User', optional: true

  enum :purpose, Commerce::MessagingConsent::PURPOSES
  enum :state, Commerce::MessagingConsent::STATES, prefix: :consent
  enum :channel, PartnerConsent::CHANNELS, prefix: :channel

  validates :decision_ref, presence: true, length: { maximum: 128 }
  validates :external_subject_id, presence: true, length: { maximum: 128 }
  validates :source, presence: true, length: { maximum: 40 }
  validates :captured_at, :received_at, :outcome, presence: true

  scope :applied, -> { where(outcome: Partners::Consents::APPLIED) }
  scope :for_scope, lambda { |store, contact, purpose, channel|
    where(commerce_store_id: store.id, contact_id: contact.id, purpose: purpose, channel: channel)
  }
end
