# == Schema Information
#
# Table name: odoo_customer_mappings
#
# Which Odoo partner is which Lynomia account, at one destination (docs/odoo/02-architecture.md §4).
#
# WHY THIS CANNOT BE DERIVED. The chain is Lynomia Account -> BillingSubscription -> Stripe customer -> Odoo
# res.partner, and the last hop has no key. Two unrelated Lynomia accounts may legitimately share a billing
# email, and the destination database holds partners belonging to several other businesses, so matching on a
# name or an email would merge books that must stay apart. This row records the decision once, and three
# unique indexes make the merge impossible rather than merely unlikely:
#
#   uniq_odoo_customer_mapping_per_account           one partner per account
#   uniq_odoo_customer_mapping_per_partner           one account per partner  <- the merge guard
#   uniq_odoo_customer_mapping_per_stripe_customer   one account per Stripe customer
class Odoo::CustomerMapping < ApplicationRecord
  self.table_name = 'odoo_customer_mappings'

  # How the partner was decided. A reader must be able to tell "we created this partner" from "we adopted a
  # partner that was already there", because the two have different consequences if the mapping turns out to
  # be wrong.
  MATCHED_BY = %w[source_reference created operator].freeze

  belongs_to :destination_profile, class_name: 'Odoo::DestinationProfile',
                                   foreign_key: :odoo_destination_profile_id, inverse_of: :customer_mappings
  belongs_to :account, optional: false
  has_many :document_mappings, class_name: 'Odoo::DocumentMapping', dependent: :nullify,
                               foreign_key: :odoo_customer_mapping_id, inverse_of: :customer_mapping

  enum :state, Odoo::SyncState::STATES, prefix: :state

  validates :source_reference, presence: true
  validates :matched_by, inclusion: { in: MATCHED_BY }, allow_nil: true

  scope :unhealthy, -> { where(state: Odoo::SyncState::UNHEALTHY) }
  scope :exported, -> { where.not(odoo_partner_id: nil) }
  scope :recent_first, -> { order(updated_at: :desc, id: :desc) }

  def exported?
    odoo_partner_id.present?
  end
end
