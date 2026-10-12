# A reusable set of SLA targets, on the `sla_policies` table that already ships in the OSS schema
# (db/schema.rb:1661) and has never held a row in this fork.
#
# WHY REUSE THE TABLE: its columns are exactly the ones a support-case policy needs -- a name, a description, a
# first-response threshold, a resolution threshold and a business-hours switch -- and reusing it means P9 adds no
# table for SLA configuration at all. Chatwoot's own SLA engine lived in enterprise/, which is permanently absent
# from this fork (ChatwootApp.extensions == ['custom']), so nothing else will ever claim these rows. None of the
# code here is derived from that engine.
#
# `next_response_time_threshold` is left unused: a case has no "next response" concept, and inventing one to fill
# a column would be the wrong way round. One unused nullable column, recorded rather than hidden.
class Support::SlaPolicy < ApplicationRecord
  self.table_name = 'sla_policies'

  # Thresholds are stored in seconds, as floats, which is what the column type already is.
  MAX_THRESHOLD_SECONDS = 365.days.to_i

  belongs_to :account
  has_many :support_tickets, class_name: 'Support::Ticket', dependent: :nullify, inverse_of: :sla_policy

  validates :name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 1000 }, allow_nil: true
  validates :first_response_time_threshold, :resolution_time_threshold,
            numericality: { greater_than: 0, less_than_or_equal_to: MAX_THRESHOLD_SECONDS }, allow_nil: true
  validate :at_least_one_threshold

  def business_hours? = only_during_business_hours?

  private

  # A policy with neither target cannot do anything, and attaching one would make a case look governed when it is
  # not. Fail at the boundary rather than silently never computing a due time.
  def at_least_one_threshold
    return if first_response_time_threshold.present? || resolution_time_threshold.present?

    errors.add(:base, 'must set a first response or a resolution target')
  end
end
