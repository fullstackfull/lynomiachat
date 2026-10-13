# Lynomia's own response target for one billing plan, or for the installation
# (docs/platform-support/12-refresh-against-product-refinement.md §1 M2).
#
# NO THRESHOLD VALUE IS CHOSEN IN CODE. Every target is a column on a row an operator enters, so the desk
# tightens later by adding rows and never by a migration. Until rows exist the engine resolves no policy and
# the staff desk says "no SLA policy applies" rather than inventing a number -- which is also why these targets
# are never serialized to a tenant: they are Lynomia's internal commitment, and publishing one would turn an
# operational goal into a contractual claim.
#
# THE MAPPING KEY IS `billing_plan_id` AND NEVER A PLAN NAME. `billing_plans` has no tier and no code column,
# and `name` is free text an operator may edit, so an id is the only stable key available. A NULL
# `billing_plan_id` is the installation default; the database allows exactly one such row.
#
# Thresholds are integer SECONDS. The tenant SLA table stores floats and that already forced a `.round` in its
# clock; sub-second precision in a human response target measures nothing.
class PlatformSupport::SlaPolicy < ApplicationRecord
  self.table_name = 'platform_support_sla_policies'

  MAX_THRESHOLD_SECONDS = 365.days.to_i

  belongs_to :billing_plan, optional: true

  has_many :tickets, class_name: 'PlatformSupport::Ticket', dependent: :nullify, inverse_of: :sla_policy

  validates :name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 1000 }, allow_nil: true
  validates :first_response_time_threshold, :resolution_time_threshold,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_THRESHOLD_SECONDS },
            allow_nil: true
  validate :at_least_one_threshold

  scope :active, -> { where(active: true) }
  # The fallback when the subject account's plan has no policy of its own.
  scope :installation_default, -> { where(billing_plan_id: nil) }

  private

  # A policy with neither target cannot do anything, and applying one would make a ticket look governed when it
  # is not. The same validation, and the same reason, as the tenant helpdesk's own policy model.
  def at_least_one_threshold
    return if first_response_time_threshold.present? || resolution_time_threshold.present?

    errors.add(:base, 'must set a first response or a resolution target')
  end
end
