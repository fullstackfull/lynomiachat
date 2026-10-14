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

  # KEEP IN STEP WITH Commerce::Providers::REGISTRY. Nothing reconciles the two: a provider
  # present only in the registry is constructible but fails `validates :provider, inclusion:`
  # here, on Commerce::Cart and on Commerce::ActionRun, so it can be read but never connected.
  # The duplication is upstream's; the comment is so the next person does not find out the hard
  # way. A spec asserts the two lists match.
  PROVIDERS = %w[woocommerce salla zid shopify storesyria].freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :customer_links, class_name: 'Commerce::CustomerLink', foreign_key: :commerce_store_id, inverse_of: :store,
                            dependent: :delete_all
  # What is operationally known about this store right now (docs/product-refinement/09-commerce-operations.md).
  # The foreign key cascades in the database too, so a path that deletes a store without loading it cannot
  # leave an orphaned snapshot behind either.
  has_one :health, class_name: 'Commerce::StoreHealth', foreign_key: :commerce_store_id, inverse_of: :store,
                   dependent: :delete

  enum :status, { active: 0, disabled: 1, needs_reauth: 2, disconnected: 3 }

  # Stores the plan's `stores` limit counts: a disconnected store keeps only its history.
  scope :connected, -> { where.not(status: :disconnected) }

  serialize :credentials, coder: JSON
  encrypts :credentials

  validates :provider, inclusion: { in: PROVIDERS }
  validates :name, :base_url, :external_store_id, presence: true
  validates :external_store_id, uniqueness: { scope: :provider }
  validate :credentials_encryptable, if: -> { credentials.present? }

  # A store losing its authorization is an operational problem a human has to act on, so it is recorded as one
  # (docs/product-refinement/09-commerce-operations.md §incidents). Recorded HERE rather than in the services
  # that flip the status, because there are six of them -- Commerce::StoreConnection#attach,
  # #rotate_credentials, #enable, #credentials_rejected and #disconnect, plus
  # Commerce::TokenManager#needs_reauth! -- and this is the one place every one of them passes through. A
  # seventh writer added later is covered without anybody remembering to be.
  after_update_commit :record_authorization_signal, if: :status_previously_changed?

  def serializable_hash(options = nil)
    super.except('credentials')
  end

  private

  # Opened when the merchant's authorization is gone, resolved by the store working again -- and resolved for a
  # DISCONNECTED store too, because a merchant who disconnected their store did not leave an incident behind.
  #
  # Through Operations::SignalRecorder, which is the only writer of a signal and never raises into its caller:
  # observability must not be able to fail a status change that the product needs to make.
  def record_authorization_signal
    recorder = Operations::SignalRecorder.new(source: :commerce_store, account: account, subject: self)
    return recorder.record(:reauthorization_required, severity: :critical, detail: { provider: provider, store_id: id }) if needs_reauth?

    recorder.resolve(:reauthorization_required)
  end

  # Credentials are never stored in plaintext: without Active Record encryption keys the store cannot be saved.
  def credentials_encryptable
    errors.add(:credentials, :encryption_not_configured) unless Chatwoot.encryption_configured?
  end
end
