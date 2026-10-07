# Lynomia Campaigns (docs/campaigns/02-recipients.md): a campaign owns the recipients it addressed.
# delete_all rather than destroy_async because a recipient has no callbacks and a deleted campaign
# has nothing left to report.
module Custom::Campaign
  extend ActiveSupport::Concern

  included do
    has_many :campaign_recipients, dependent: :delete_all
  end
end
