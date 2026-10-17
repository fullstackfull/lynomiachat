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

    # THE PARTNER INSTALLATION THIS CAMPAIGN CAME FROM, or nil for one created in Lynomia
    # itself. Nil is what marks a campaign as not partner-originated, which is every campaign
    # that existed before partner consent did -- so none of them changes meaning, and the
    # partner checks at the send boundary are simply not reached for them.
    belongs_to :commerce_store, class_name: 'Commerce::Store', optional: true
  end
end
