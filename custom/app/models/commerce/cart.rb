# The durable lifecycle of one provider cart (docs/commerce-production/05-cart-state-design.md).
#
# Two states, because two is what the provider's events can establish:
#
#   abandoned   the provider said this cart was abandoned (Zid: `abandoned_cart.created`, after its own
#               provider-defined interval of inactivity). Lynomia runs no inactivity timer, so a provider that goes
#               silent cannot produce this state — silence is not a signal.
#   completed   the provider said the cart was completed (Zid: `abandoned_cart.completed`). This proves CHECKOUT
#               COMPLETION and nothing more.
#
# There is deliberately no `recovered` state. Completion does not prove that Lynomia's outreach caused it, and Zid's
# own schema carries `reminders_count` and a `whatsapp_message`, so the provider may be sending reminders of its own.
# Recovery is therefore a reading of two recorded facts, never a stored state — see #post_target_completion?.
#
# There is also no `active` state: the provider never announces a live cart. The first thing it ever says about a cart
# is that it has been abandoned.
class Commerce::Cart < ApplicationRecord
  self.table_name = 'commerce_carts'

  # Forward only. A completed cart never returns to abandoned, whatever order the events arrive in.
  enum :state, { abandoned: 0, completed: 1 }

  belongs_to :account
  belongs_to :commerce_store, class_name: 'Commerce::Store'
  belongs_to :contact, optional: true
  belongs_to :commerce_customer_link, class_name: 'Commerce::CustomerLink', optional: true

  # Deterministic for the same reason Commerce::CustomerLink's is: guest references are derived from an email or an
  # E.164 phone, and they have to be queryable.
  encrypts :external_customer_id, deterministic: true

  validates :provider, inclusion: { in: Commerce::Store::PROVIDERS }
  validates :provider_cart_id, presence: true, uniqueness: { scope: :commerce_store_id }
  validates :first_seen_at, :last_provider_event_at, presence: true
  validate :store_in_account

  scope :targeted, -> { where.not(targeted_at: nil) }
  scope :order_attributed, -> { where.not(provider_order_id: nil) }

  # True when Lynomia's outreach was accepted for sending BEFORE the provider reported completion. This is the
  # strongest statement the data supports, and it is a time ordering, not a proof of cause: the shopper may have
  # returned on their own, or in response to the store's own reminder. Named for what it measures.
  def post_target_completion?
    completed? && targeted_at.present? && completed_at.present? && completed_at > targeted_at
  end

  # Completion with no outreach from Lynomia at all.
  def untargeted_completion? = completed? && targeted_at.nil?

  def order_attributed? = provider_order_id.present?

  private

  def store_in_account
    return if commerce_store.nil? || commerce_store.account_id == account_id

    errors.add(:commerce_store, 'must belong to the same account')
  end
end
