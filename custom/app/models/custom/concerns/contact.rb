# Lynomia Campaigns (docs/campaigns/02-recipients.md): a contact's campaign recipients go with it.
# destroy_async rather than delete_all because a contact is deleted interactively and the rows are
# per-campaign, so the work belongs off the request.
module Custom::Concerns::Contact
  extend ActiveSupport::Concern

  included do
    has_many :campaign_recipients, dependent: :destroy_async
    # Lynomia Support: a contact's cases survive the contact, with contact_id nullified by the foreign key, so
    # the account keeps its support history. No `dependent:` for the same reason.
    has_many :support_tickets, class_name: 'Support::Ticket', inverse_of: :contact, dependent: nil
    # Lynomia unified identity: the additional numbers and addresses this contact owns
    # (docs/p10/03-unified-customer-identity.md). The foreign key is ON DELETE CASCADE, so no `dependent:`;
    # an identity has no meaning without its contact.
    has_many :contact_identities, dependent: nil

    # `contacts` and `contact_identities` must agree on who owns a value, and no index spans both tables: the
    # one on `contacts` cannot see a linked identity and the one on `contact_identities` cannot see a primary
    # field. Contacts::IdentityLinker checks both before it writes a row; this is the same check from the other
    # side, so an agent cannot give a contact a phone number or an email address that is already linked to
    # somebody else.
    #
    # Conditional on the two columns actually changing, which is what keeps it off the hot inbound path: a
    # conversation, a message or a `last_activity_at` touch runs no extra query. A contact merge passes it
    # because the mergee's identity rows move to the base before the base takes over its attributes.
    validate :primary_identities_not_linked_elsewhere, if: -> { phone_number_changed? || email_changed? }
  end

  private

  def primary_identities_not_linked_elsewhere
    claimed_identity_types.each do |identity_type, column|
      next unless identity_claimed_elsewhere?(identity_type, self[column])

      errors.add(column, I18n.t('errors.contacts.identities.linked_elsewhere'))
    end
  end

  def identity_claimed_elsewhere?(identity_type, value)
    rows = ContactIdentity.where(account_id: account_id, identity_type: identity_type, value: value)
    # `where.not(contact_id: nil_id)` matches nothing in SQL, so a contact being created has to ask the
    # question without that clause -- it owns no rows yet.
    rows = rows.where.not(contact_id: id) if persisted?
    rows.exists?
  end

  def claimed_identity_types
    {}.tap do |types|
      types[:phone] = :phone_number if phone_number_changed? && phone_number.present?
      types[:email] = :email if email_changed? && email.present?
    end
  end
end
