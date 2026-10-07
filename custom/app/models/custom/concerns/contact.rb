# Lynomia Campaigns (docs/campaigns/02-recipients.md): a contact's campaign recipients go with it.
# destroy_async rather than delete_all because a contact is deleted interactively and the rows are
# per-campaign, so the work belongs off the request.
module Custom::Concerns::Contact
  extend ActiveSupport::Concern

  included do
    has_many :campaign_recipients, dependent: :destroy_async
  end
end
