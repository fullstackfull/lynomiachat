# Lynomia Campaigns (docs/campaigns/02-recipients.md): a contact's campaign recipients go with it.
# destroy_async rather than delete_all because a contact is deleted interactively and the rows are
# per-campaign, so the work belongs off the request.
module Custom::Concerns::Contact
  extend ActiveSupport::Concern

  included do
    has_many :campaign_recipients, dependent: :destroy_async
    # Lynomia Support: a contact's cases survive the contact, with contact_id nullified by the foreign key, so
    # the account keeps its support history. No `dependent:` for the same reason.
    has_many :support_tickets, class_name: 'Support::Ticket', inverse_of: :contact, dependent: nil
  end
end
