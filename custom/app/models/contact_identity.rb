# An additional phone number or email address that belongs to a Contact (docs/p10/03-unified-customer-identity.md).
#
# One row is one identity value, normalized, and the account-scoped unique index means it belongs to exactly one
# contact. Rows are only ever created through Contacts::IdentityLinker, which is where the normalization and the
# cross-check against `contacts`' own primary fields live; the validations here are the backstop for a direct
# write in a console or a spec, not a second entry point.
#
# `value` is a customer's phone number or email address, so it is never written to a log line or an audit row.
class ContactIdentity < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :linked_by, class_name: 'User', optional: true

  enum identity_type: { phone: 0, email: 1 }
  # agent_linked: an agent said these are the same person. merged: a contact merge absorbed a value that was a
  # verified primary field on the contact it destroyed. Neither is a similarity judgement.
  enum source: { agent_linked: 0, merged: 1 }, _prefix: :source

  validates :value, presence: true, uniqueness: { scope: [:account_id, :identity_type] }
  validates :value, format: { with: Contacts::Phone::STRUCTURAL_FORMAT }, if: :phone?
  validates :value, format: { with: Devise.email_regexp }, if: :email?

  scope :for_value, ->(identity_type, values) { where(identity_type: identity_type, value: values) }
end
