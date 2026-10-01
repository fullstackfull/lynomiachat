# == Schema Information
#
# Table name: commerce_stores
#
#  id                :bigint           not null, primary key
#  base_url          :string           not null
#  credentials       :text
#  external_store_id :string           not null
#  metadata          :jsonb            not null
#  name              :string           not null
#  provider          :string           not null
#  settings          :jsonb            not null
#  status            :integer          default("active"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  created_by_id     :bigint
#
# Indexes
#
#  index_commerce_stores_on_account_id_and_provider           (account_id,provider)
#  index_commerce_stores_on_created_by_id                     (created_by_id)
#  index_commerce_stores_on_provider_and_external_store_id    (provider,external_store_id) UNIQUE
#
# Lynomia Commerce: one connected store. A store belongs to exactly one account at a time; its credentials are
# encrypted at rest and never leave the backend (docs/commerce/04-security-and-tenancy.md).
class Commerce::Store < ApplicationRecord
  self.table_name = 'commerce_stores'

  PROVIDERS = %w[woocommerce salla zid shopify].freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :customer_links, class_name: 'Commerce::CustomerLink', foreign_key: :commerce_store_id, inverse_of: :store,
                            dependent: :delete_all

  enum :status, { active: 0, disabled: 1, needs_reauth: 2, disconnected: 3 }

  # Stores the plan's `stores` limit counts: a disconnected store keeps only its history.
  scope :connected, -> { where.not(status: :disconnected) }

  serialize :credentials, coder: JSON
  encrypts :credentials

  validates :provider, inclusion: { in: PROVIDERS }
  validates :name, :base_url, :external_store_id, presence: true
  validates :external_store_id, uniqueness: { scope: :provider }
  validate :credentials_encryptable, if: -> { credentials.present? }

  def serializable_hash(options = nil)
    super.except('credentials')
  end

  private

  # Credentials are never stored in plaintext: without Active Record encryption keys the store cannot be saved.
  def credentials_encryptable
    errors.add(:credentials, :encryption_not_configured) unless Chatwoot.encryption_configured?
  end
end
