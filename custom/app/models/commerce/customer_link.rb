# == Schema Information
#
# Table name: commerce_customer_links
#
#  id                   :bigint           not null, primary key
#  match_source         :integer          not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  commerce_store_id    :bigint           not null
#  confirmed_by_id      :bigint
#  contact_id           :bigint           not null
#  external_customer_id :string           not null
#
# Indexes
#
#  index_commerce_customer_links_on_account_id                     (account_id)
#  index_commerce_customer_links_on_store_and_contact  (commerce_store_id,contact_id) UNIQUE
#  index_commerce_customer_links_on_confirmed_by_id                (confirmed_by_id)
#  index_commerce_customer_links_on_contact_id                     (contact_id)
#
# Lynomia Commerce: the store customer a contact was matched to. `external_customer_id` is the store's customer id,
# or "guest:<normalized email or E.164 phone>" for guest checkouts, so it is encrypted like other identifiers.
#
# A `suppressed` row is a link an agent removed: the contact counts as not linked in that store, and its phone no
# longer links it automatically (a match is offered instead) until someone links a customer by hand.
class Commerce::CustomerLink < ApplicationRecord
  self.table_name = 'commerce_customer_links'

  belongs_to :account
  belongs_to :store, class_name: 'Commerce::Store', foreign_key: :commerce_store_id, inverse_of: :customer_links
  belongs_to :contact
  belongs_to :confirmed_by, class_name: 'User', optional: true
  has_one :contact_metric, class_name: 'Commerce::ContactMetric', foreign_key: :commerce_customer_link_id, inverse_of: :customer_link,
                           dependent: :delete

  enum :match_source, { external_id: 0, verified_phone: 1, verified_email: 2, manual: 3, suppressed: 4 }

  encrypts :external_customer_id, deterministic: true

  validates :external_customer_id, presence: true
  validates :contact_id, uniqueness: { scope: :commerce_store_id }
  validate :same_account

  # The orders summed for audiences belonged to the customer this link no longer counts (docs/audience/03-commerce-query-model.md).
  after_update :drop_contact_metric, if: -> { saved_change_to_external_customer_id? || (saved_change_to_match_source? && suppressed?) }

  private

  def drop_contact_metric
    Commerce::ContactMetric.where(commerce_customer_link_id: id).delete_all
  end

  def same_account
    return if store.blank? || contact.blank?
    return if store.account_id == account_id && contact.account_id == account_id

    errors.add(:account, :invalid)
  end
end
