# Reading what a contact import asks for, at the request boundary.
#
# An import carries more than a file now: the labels every row should get, the country to assume for the rows that
# name none, and what to do about a contact the account already has. None of that needs a column — `DataImport`
# already has a `source_metadata` jsonb, and the import's own job reads the batch's choices back out of it, so the
# whole feature adds no schema (docs/contacts/04-bulk-import.md).
#
# Everything is checked here rather than in the job, because a job cannot answer a request: an unknown label, a
# country that is not a country or a policy that is not one of the two returns 422 with the same
# `{ message, attributes, errors, error_types }` body every other contact validation failure returns, instead of
# failing silently an hour later inside a queue.
module ContactImportParams
  extend ActiveSupport::Concern
  include ContactLabelParams
  include ContactImportFile

  private

  # The file and the batch's choices are written together, so a job can never pick the import up with one and not
  # the other.
  def create_contact_import(attachment)
    ActiveRecord::Base.transaction do
      import = Current.account.data_imports.create!(data_type: 'contacts', initiated_by: Current.user,
                                                    source_metadata: import_metadata)
      import.import_file.attach(attachment)
    end
  end

  def render_import_blank
    render json: { error: I18n.t('errors.contacts.import.failed') }, status: :unprocessable_entity
  end

  # The preview's own answer, plus the id of the stored file, which is how the import that follows avoids sending
  # it again. The paste path has nothing to store: a pasted list is a few kilobytes of text.
  def contact_import_preview(content)
    preview = DataImport::ContactPreview.new(Current.account, raw_csv: content, options: import_metadata.symbolize_keys).perform
    signed_id = import_blob_signed_id
    return preview if signed_id.blank?

    preview.merge(import_file_blob_id: signed_id)
  end

  # @return [Hash] the batch's choices, as the job will read them back.
  def import_metadata
    {
      'labels' => requested_label_titles(Current.account.contacts.new),
      'default_country' => requested_default_country,
      'duplicate_policy' => requested_duplicate_policy
    }
  end

  # An explicit country, or nil. Never inferred from the account's locale, its timezone, an inbox or a business
  # number — the one region signal this phase accepts is one somebody chose (docs/contacts/03-phase-b.md §B4).
  def requested_default_country
    code = params[:default_country].presence
    return if code.blank?

    country = code.to_s.strip.upcase
    return country if TelephoneNumber::Country.find(country.downcase.to_sym)

    invalid_import!(:not_a_country, I18n.t('errors.contacts.import.not_a_country', country: code))
  end

  def requested_duplicate_policy
    policy = params[:duplicate_policy].presence
    return DataImport::ContactRows::DEFAULT_DUPLICATE_POLICY if policy.blank?
    return policy if DataImport::ContactRows::DUPLICATE_POLICIES.include?(policy)

    invalid_import!(:not_a_duplicate_policy,
                    I18n.t('errors.contacts.import.not_a_duplicate_policy',
                           policies: DataImport::ContactRows::DUPLICATE_POLICIES.join(', ')))
  end

  # On `:base`, not on an invented attribute name: activemodel reads the attribute off the record to build an
  # error's message (`ActiveModel::Error.generate_message`), with no `respond_to?` guard, so any name that is not
  # a real attribute raises while the 422 is being rendered. The machine-readable part a client needs is the
  # error's type, which `error_types` carries either way.
  def invalid_import!(type, message)
    contact = Current.account.contacts.new
    contact.errors.add(:base, type, message: message)
    raise ActiveRecord::RecordInvalid, contact
  end
end
