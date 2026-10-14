# A ceiling an integration includes with its own product, for one account.
#
# See the migration for why this is not a BillingEntitlementOverride and why the two compose by
# MAX rather than by sum.
class PlatformAppEntitlementGrant < ApplicationRecord
  belongs_to :platform_app
  belongs_to :account

  validates :resource, presence: true, inclusion: { in: BillingPlan::LIMIT_KEYS }
  validates :limit_value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_resource, ->(resource) { where(resource: resource.to_s) }

  # The highest ceiling any integration includes for this account, or nil when none does.
  #
  # MAX ACROSS INTEGRATIONS for the same reason as max against the plan: two integrations each
  # including seats is not a reason to add them together, and taking the lower would withdraw
  # something the merchant was promised.
  def self.ceiling_for(account, resource)
    return nil if account.nil?

    where(account_id: account.id).for_resource(resource).maximum(:limit_value)
  end
end
