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
class Commerce::CustomerLink < ApplicationRecord
  self.table_name = 'commerce_customer_links'

  belongs_to :account
  belongs_to :store, class_name: 'Commerce::Store', foreign_key: :commerce_store_id, inverse_of: :customer_links
  belongs_to :contact
  belongs_to :confirmed_by, class_name: 'User', optional: true

  enum :match_source, { external_id: 0, verified_phone: 1, verified_email: 2, manual: 3 }

  encrypts :external_customer_id, deterministic: true

  validates :external_customer_id, presence: true
  validates :contact_id, uniqueness: { scope: :commerce_store_id }
  validate :same_account

  private

  def same_account
    return if store.blank? || contact.blank?
    return if store.account_id == account_id && contact.account_id == account_id

    errors.add(:account, :invalid)
  end
end
