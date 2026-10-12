# A campaign owns the recipient snapshot it produced
# (docs/p-final/clean-room/specs/D-campaign-recipient-outcomes.md §3).
#
# The mirror of the association a contact already has (custom/app/models/custom/concerns/contact.rb:8), and the
# one the per-campaign analytics read through.
#
# No `dependent:`, because `campaign_recipients.campaign_id` carries an ON DELETE CASCADE foreign key
# (db/schema.rb:1962): the database removes the rows, and a second mechanism would only be a second thing to
# keep in step.
module Custom::Campaign
  extend ActiveSupport::Concern

  included do
    has_many :campaign_recipients, dependent: nil
  end
end
