# Turning one row of a contacts CSV into a contact.
#
# Reading and writing are separate on purpose. `find_existing` only queries, so the preview that runs before an
# import can classify a whole file without touching anything, and the importer decides for itself whether a match
# is updated or left as it is. Before Lynomia's bulk-import work the lookup saved the contact it found, which made
# a dry run impossible and meant a mid-file failure left part of the account already changed.
class DataImport::ContactManager
  def initialize(account)
    @account = account
  end

  # Every contact the account already has that any of these identities could name, loaded in three queries rather
  # than three per row. A caller that classifies a whole batch at once — the preview — looks first; the import's
  # own pass over a file it is streaming does not, and keeps the row-by-row lookup below.
  #
  # @param identities [Array<Array>] `[:identifier | :email | :phone_number, value]` pairs.
  def preload(identities)
    grouped = identities.compact.group_by(&:first).transform_values { |pairs| pairs.map(&:last).uniq }
    @known = {
      identifier: index_by(:identifier, grouped[:identifier]),
      email: index_by(:email, grouped[:email]),
      phone_number: index_by(:phone_number, grouped[:phone_number])
    }
  end

  # The contact this row names, when the account already has one. Read-only.
  #
  # @param params [Hash] the row.
  # @param region [String, nil] the explicit country for this row, for matching a local phone number.
  # @return [Contact, nil]
  def find_existing(params, region: nil)
    return from_preloaded(params, region) if @known

    find_contact_by_identifier(params) ||
      find_contact_by_email(params) ||
      find_contact_by_phone_number(params, region)
  end

  # The row as a new, unsaved contact.
  def build_new(params, region: nil)
    contact = @account.contacts.new(identity_attributes(params, region))
    apply_attributes(contact, params, region)
  end

  # The row written onto a contact the account already has, in memory. A column the row leaves blank never clears
  # what is stored: only a value the row actually carries overwrites one. Assigning without saving is what lets
  # the preview ask whether the update *would* be valid.
  def assign_existing(contact, params, region: nil)
    contact.assign_attributes(identity_attributes(params, region).compact_blank)
    apply_attributes(contact, params, region)
  end

  # The same, saved.
  def update_existing(contact, params, region: nil)
    assign_existing(contact, params, region: region).tap(&:save)
  end

  # Find and update, or build. The importer's single call for a row it has decided to write.
  def build_contact(params, region: nil)
    existing = find_existing(params, region: region)
    return build_new(params, region: region) if existing.nil?
    return update_existing(existing, params, region: region) if existing.valid?

    # A contact that is already invalid for some other reason is left alone rather than saved into a worse state;
    # the row's attributes are still applied in memory so the caller sees what it asked for.
    apply_attributes(existing, params, region)
  end

  # E.164 for what a row carries, using the row's own country when it names one.
  #
  # A real number parses: "+965...", "00965..." and a local "0551112233" once the country is known. Everything
  # else keeps the shape this importer has always produced — a bare "+" in front — because `Contact`'s own rule is
  # structural (`/\A\+[1-9]\d{1,14}\z/`), so numbers that are well-formed without being real numbers have always
  # been accepted here and tightening that belongs to the model, not to one of its writers. What this does fix is
  # the case the old blind prefix got wrong: a local number with a known country used to become "+0551112233",
  # which `Contact` then rejected, and now becomes the right number instead.
  def self.phone_number(raw, region = nil)
    return if raw.to_s.strip.blank?

    Contacts::Phone.e164(raw, region) || prefixed(raw)
  end

  def self.prefixed(raw)
    number = raw.to_s.strip
    number.start_with?('+') ? number : "+#{number}"
  end
  private_class_method :prefixed

  private

  def index_by(column, values)
    return {} if values.blank?

    @account.contacts.where(column => values).index_by { |contact| contact.public_send(column) }
  end

  # Identity order is the same as the query path's: identifier, then email, then phone number.
  def from_preloaded(params, region)
    @known[:identifier][params[:identifier].presence] ||
      @known[:email][params[:email].presence&.downcase] ||
      @known[:phone_number][self.class.phone_number(params[:phone_number], region)]
  end

  def identity_attributes(params, region)
    {
      identifier: params[:identifier],
      email: params[:email],
      phone_number: self.class.phone_number(params[:phone_number], region)
    }
  end

  def find_contact_by_identifier(params)
    return if params[:identifier].blank?

    @account.contacts.find_by(identifier: params[:identifier])
  end

  def find_contact_by_email(params)
    return if params[:email].blank?

    @account.contacts.from_email(params[:email])
  end

  def find_contact_by_phone_number(params, region)
    number = self.class.phone_number(params[:phone_number], region)
    return if number.blank?

    @account.contacts.find_by(phone_number: number)
  end

  # String keys, because `Contacts::SyncAttributes` reads `additional_attributes['city']` to fill the `location`
  # column; symbol keys left it unset on every imported contact.
  def apply_attributes(contact, params, region)
    contact.name = params[:name] if params[:name].present?
    contact.additional_attributes ||= {}
    contact.additional_attributes['company_name'] = params[:company_name] if params[:company_name].present?
    contact.additional_attributes['city'] = params[:city] if params[:city].present?
    # The country this row's number was read with, under the key the contact form reads as its region, so editing
    # the contact later starts from the same country the import used (docs/contacts/03-phase-b.md §B4).
    contact.additional_attributes['country_code'] = region if region.present?
    contact.assign_attributes(custom_attributes: contact.custom_attributes.merge(params.except(:identifier, :email, :name, :phone_number)))
    sync_attributes(contact)
  end

  # `Contact.import` runs validation callbacks but not `before_save`, so the sync every ordinary write performs has
  # to be performed here too. Without it a bulk-inserted contact keeps the `visitor` contact_type it was created
  # with, and an account with `crm_v2` enabled resolves its contacts list to leads only — so the contacts somebody
  # just imported would not be in it.
  def sync_attributes(contact)
    Contacts::SyncAttributes.new(contact).perform
    contact
  end
end
