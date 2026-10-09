# The one way a ContactIdentity row is created (docs/p10/03-unified-customer-identity.md §4).
#
# Linking an identity decides where the next message from that number or address is delivered, so it is a
# routing decision, not a note. Everything that makes it safe is here rather than spread across the callers:
# the normalization, the check that the value is not already somebody else's, and the refusal to guess.
#
# It never merges. A value that belongs to another contact is reported as a conflict and the agent decides --
# which is the same stance ContactIdentifyAction already takes when two contacts disagree
# (`mergable_phone_contact?` refuses to let a phone match overwrite an email match).
#
# It reports rather than raises, because every outcome here is an ordinary product outcome the caller must
# render or count: the controller turns a conflict into 422 and a contact merge turns one into a skipped row
# without rolling back the merge.
class Contacts::IdentityLinker
  # The account feature that allows an identity to be RECORDED. Deliberately not consulted when one is READ:
  # a link an account made while the feature was on must keep routing its messages if the feature is later
  # turned off, because silently sending a customer's replies somewhere else is worse than either state.
  FEATURE = 'lynomia_unified_identity'.freeze

  # linked: a new row. already_linked: this contact already owns the value, as a row or as its own primary field,
  # so there is nothing to do. conflict: another contact owns it. invalid: not a phone number or email address
  # this app can normalize. disabled: the account does not have the feature.
  Result = Struct.new(:status, :identity, :conflict_contact_id, keyword_init: true)

  def initialize(contact:, identity_type:, value:, source: :agent_linked, linked_by: nil)
    @contact = contact
    @identity_type = identity_type.to_s
    @raw_value = value
    @source = source
    @linked_by = linked_by
  end

  def link
    return Result.new(status: :disabled) unless @contact.account.feature_enabled?(FEATURE)
    return Result.new(status: :invalid) unless ContactIdentity.identity_types.key?(@identity_type)

    value = normalized_value
    return Result.new(status: :invalid) if value.blank?

    owner = current_owner(value)
    return Result.new(status: :already_linked, identity: existing_row(value)) if owner == @contact.id
    return Result.new(status: :conflict, conflict_contact_id: owner) if owner

    create(value)
  end

  private

  def normalized_value
    @identity_type == 'phone' ? normalized_phone : normalized_email
  end

  # Contacts::Phone.e164 first, the app's one E.164 path, using the contact's own recorded country when it has
  # one -- the same explicit region source the CSV importer uses. There is no default region, so a local number
  # typed without a country has nowhere to go and is reported invalid rather than stored as a guess
  # (app/services/contacts/phone.rb).
  #
  # A number that already carries its country is kept even when `e164` will not vouch for it, because `e164`
  # asks whether the number is REAL while `contacts.phone_number` only asks whether it is well formed
  # (`STRUCTURAL_FORMAT`). The CSV importer stores numbers that pass the second test and fail the first, so a
  # stricter rule here would quietly refuse to carry a number a contact already has -- which is exactly what a
  # merge asks it to do. One rule for what may be stored, the stricter one for what may be typed.
  def normalized_phone
    raw = @raw_value.to_s.strip
    Contacts::Phone.e164(raw, @contact.additional_attributes['country_code']) ||
      (raw if raw.match?(Contacts::Phone::STRUCTURAL_FORMAT))
  end

  def normalized_email
    email = @raw_value.to_s.strip.downcase
    email if email.match?(Devise.email_regexp)
  end

  # Both domains, because `contacts` holds one value of each type in its own unique columns and
  # `contact_identities` holds the rest. A value is deterministic only if exactly one contact can claim it.
  def current_owner(value)
    existing_row(value)&.contact_id || primary_field_owner(value)
  end

  def existing_row(value)
    ContactIdentity.find_by(account_id: @contact.account_id, identity_type: @identity_type, value: value)
  end

  def primary_field_owner(value)
    column = @identity_type == 'phone' ? :phone_number : :email
    Contact.where(account_id: @contact.account_id).find_by(column => value)&.id
  end

  # The unique index is the real guarantee: two agents linking the same value at the same time both pass the
  # check above and one of the inserts loses, which is reported as the conflict it is.
  def create(value)
    identity = ContactIdentity.create!(
      account_id: @contact.account_id, contact: @contact,
      identity_type: @identity_type, value: value, source: @source, linked_by: @linked_by
    )
    Result.new(status: :linked, identity: identity)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    owner = current_owner(value)
    # Anything other than "somebody already owns it" is a real bug and stays loud.
    raise unless owner

    Result.new(status: :conflict, conflict_contact_id: owner)
  end
end
