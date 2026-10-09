# Lynomia unified identity, inbound side: a message from a number or an address an agent has linked to a
# contact reaches that contact instead of creating a new one (docs/p10/03-unified-customer-identity.md §5).
#
# Purely a fallback. The OSS order -- identifier, then email, then phone and its provider-quirk candidates, then
# an Instagram source_id already seen on a Facebook page -- is untouched and still decides every message it can
# answer. This runs only where that order returned nothing, which is the path that was about to create a new
# contact, so the cost is one indexed equality lookup on the rare branch and nothing at all on the common one.
#
# Deterministic by construction: `contact_identities` is UNIQUE on (account_id, identity_type, value), so a
# value resolves to exactly one contact or to none. Email is tried before phone, matching the OSS precedence.
# Nothing here compares names, avatars, usernames or email local-parts, and nothing merges.
module Custom::ContactInboxWithContactBuilder
  private

  def find_contact
    super || find_contact_by_linked_identity
  end

  # Downcased for the same reason the OSS email lookup downcases (`Contact.from_email`): a stored identity is
  # always lower case, because both Contacts::IdentityLinker and Contact#prepare_contact_attributes make it so.
  # Without this, a provider that reports a mixed-case address would miss the link and then try to create a
  # contact holding a value this account has already linked, which the Contact validation refuses.
  def find_contact_by_linked_identity
    identity = linked_identity(:email, contact_attributes[:email]&.downcase) ||
               linked_identity(:phone, phone_number_candidates)
    identity&.contact
  end

  def linked_identity(identity_type, values)
    values = Array(values).compact_blank.uniq
    return if values.blank?

    ContactIdentity.where(account_id: account.id).for_value(identity_type, values).first
  end

  # The same set the OSS phone lookup tries, so a linked number is matched through the provider quirks
  # (Argentina's 9, Brazil's ninth digit, Mexico's 1) exactly as a primary one is.
  def phone_number_candidates
    [contact_attributes[:phone_number], *Array(contact_attributes[:phone_number_candidates])]
  end
end
