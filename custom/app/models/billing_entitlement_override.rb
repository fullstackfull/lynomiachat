# frozen_string_literal: true

# An explicit, audited commercial exception for one account (docs/p11/03-plans-entitlements.md).
#
# Three kinds, because an operator needs three different exceptions and they are not interchangeable:
#   feature  - a capability on or off regardless of the plan        (name: a config/features.yml feature name)
#   limit    - a different ceiling for a counted resource           (name: a BillingPlan::LIMIT_KEYS key)
#   channel  - a channel type sold or withheld regardless of plan   (name: a Channel:: class name)
#
# `reason` is required. An override with no stated reason is the thing nobody can explain a year later, and
# the console asks for it.
class BillingEntitlementOverride < ApplicationRecord
  KINDS = { feature: 0, limit: 1, channel: 2 }.freeze

  belongs_to :account
  belongs_to :granted_by, class_name: 'User', optional: true

  # Prefixed, so the generated predicates are kind_feature? / kind_limit? / kind_channel? rather than
  # feature? / limit? / channel? -- `limit?` in particular would shadow nothing useful and read as a
  # question about the limit column. Same reason ContactIdentity prefixes its `source` enum.
  enum kind: KINDS, _prefix: :kind

  validates :name, presence: true, uniqueness: { scope: [:account_id, :kind] }
  validates :reason, presence: true
  validates :limit_value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :value_matches_kind

  scope :live, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }
  scope :for_capability, ->(kind, name) { where(kind: kind, name: name) }

  def lapsed?
    expires_at.present? && expires_at.past?
  end

  private

  # A feature or channel override answers yes/no; a limit override answers a number. Accepting the wrong one
  # would make the entitlement service's answer silently nil.
  def value_matches_kind
    if kind_limit?
      errors.add(:limit_value, 'is required for a limit override') if limit_value.nil?
    elsif enabled.nil?
      errors.add(:enabled, "is required for a #{kind} override")
    end
  end
end
