# What a customer told an approved external PARTNER they would accept, scoped to the
# installation that captured it (docs/partner-consent/ADR-001-partner-scoped-consent.md).
#
# A GRANT HERE IS EVIDENCE FOR ONE SCOPE, NOT PERMISSION TO MESSAGE. The scope is the store,
# the purpose and the channel together, and all three have to match the send before this row
# counts for anything. That is enforced by the unique key rather than by a convention, so a
# grant captured at one merchant's checkout cannot authorise another merchant's marketing even
# if both sit in the same Lynomia account.
#
# PURPOSE AND STATE ARE THE NATIVE ENUMS, READ FROM THE NATIVE MODEL. Two consent stores that
# disagreed about what `withdrawn` means would be worse than one store with a gap, and the
# integers have to match for the two to be compared at the send boundary at all. So they are
# taken from Commerce::MessagingConsent rather than restated here; a class added there appears
# here in the same deploy.
#
# WITHDRAWAL IS SCOPE-EXACT, and that is a deliberate limit on how far one refusal reaches.
# A shopper who turns off marketing from one store has said something about that store's
# marketing. Reading it as "stop everything from everyone" would silence the parcel
# notifications they still want and the other merchant they never mentioned. An account-wide
# or global restriction is the native store's job, and the send boundary consults both.
class PartnerConsent < ApplicationRecord
  # any: the capture was not channel-specific -- a checkout tick that said "offers" without
  # naming a medium. It satisfies a send on any channel. A grant captured FOR a channel
  # satisfies only that channel, because that is all the customer was shown.
  CHANNELS = { any: 0, whatsapp: 1, sms: 2, email: 3 }.freeze

  belongs_to :platform_app
  belongs_to :account
  belongs_to :commerce_store, class_name: 'Commerce::Store'
  belongs_to :contact
  belongs_to :recorded_by, class_name: 'User', optional: true

  enum :purpose, Commerce::MessagingConsent::PURPOSES
  enum :state, Commerce::MessagingConsent::STATES, prefix: :consent
  enum :channel, CHANNELS, prefix: :channel

  validates :external_subject_id, presence: true, length: { maximum: 128 }
  validates :source, presence: true, length: { maximum: 40 }
  validates :captured_at, presence: true
  validates :contact_id, uniqueness: { scope: %i[commerce_store_id purpose channel] }
  validate :store_is_in_the_bound_account
  validate :contact_is_in_the_bound_account

  scope :blocking, -> { where(state: %i[withdrawn suppressed]) }
  scope :granted, -> { where(state: :granted) }
  # A grant captured without a channel answers for every channel; one captured for a channel
  # answers only for it.
  scope :for_channel, ->(channel) { where(channel: [CHANNELS[:any], CHANNELS.fetch(channel.to_sym)]) }

  def blocking? = consent_withdrawn? || consent_suppressed?

  private

  # CROSS-ACCOUNT ISOLATION AT THE ROW, not only at the controller. account_id is denormalised
  # from the store so eligibility can filter on it without a join; a row whose three ids
  # disagree would make that denormalisation a lie, so it cannot be written.
  def store_is_in_the_bound_account
    return if commerce_store.nil? || commerce_store.account_id == account_id

    errors.add(:commerce_store, 'belongs to a different account')
  end

  def contact_is_in_the_bound_account
    return if contact.nil? || contact.account_id == account_id

    errors.add(:contact, 'belongs to a different account')
  end
end
