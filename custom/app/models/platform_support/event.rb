# One entry in a Platform Support ticket's history
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M6).
#
# TENANT VISIBILITY IS A POSITIVE ALLOW-LIST OF 7 OF THE 18 TYPES, not a column. Default-deny is the property
# that matters: an event type added in a later phase is invisible to the customer until somebody deliberately
# lists it. A `visibility` column would default to something, and whatever it defaulted to is what a future
# contributor would get by forgetting.
#
# What is excluded, and why: `assigned`/`unassigned` (which operator holds a ticket is internal),
# `internal_note_added` (the existence of a note is internal), `priority_changed`, `subject_changed` and
# `category_changed` (internal triage), every `sla_*` (Lynomia's internal commitments), and `account_deleted`.
#
# `metadata` holds the structured before/after values the operator view reads, and is NEVER serialized to the
# tenant. PlatformSupport::EventRecorder is the only writer and gives each type a fixed payload shape, so no
# caller can hand this column a free-form hash: ids, enum values, counts and timestamps only.
#
# Written once, never edited, which is why the table has `created_at` and no `updated_at`.
class PlatformSupport::Event < ApplicationRecord
  self.table_name = 'platform_support_events'

  EVENT_TYPES = %w[created subject_changed category_changed priority_changed status_changed assigned unassigned
                   sla_policy_applied sla_first_response_met sla_first_response_breached sla_resolution_breached
                   customer_replied operator_replied internal_note_added resolved reopened closed
                   account_deleted].freeze

  CUSTOMER_VISIBLE_EVENT_TYPES = %w[created status_changed customer_replied operator_replied resolved reopened
                                    closed].freeze

  # The same three parties that may author a message, stated once rather than twice: a history row and a
  # thread row are written by the same actors, and two copies of the list would be two places to widen it.
  ACTOR_TYPES = PlatformSupport::Message::AUTHOR_TYPES

  belongs_to :ticket, class_name: 'PlatformSupport::Ticket', foreign_key: :platform_support_ticket_id,
                      inverse_of: :events

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :actor_type, inclusion: { in: ACTOR_TYPES }, allow_nil: true
  validates :actor_name, length: { maximum: 255 }, allow_nil: true

  scope :oldest_first, -> { order(created_at: :asc, id: :asc) }
  scope :customer_visible, -> { where(event_type: CUSTOMER_VISIBLE_EVENT_TYPES) }

  # The customer is told WHAT happened to their ticket, never which operator did it. The tenant serializer reads
  # this rather than `actor_name`, so the rule has one home.
  def customer_visible_actor_name
    actor_type == PlatformSupport::Message::CUSTOMER_AUTHOR_TYPE ? actor_name : nil
  end
end
