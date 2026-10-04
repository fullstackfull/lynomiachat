# Where a contact import's bytes come from, and where they go.
#
# A request can carry a CSV file, a list of numbers pasted into a textarea, or the signed id of a file an earlier
# request in the same flow already stored. Resolving which, and refusing what is not one of them, happens here;
# failures are rendered through `invalid_import!` from `ContactImportParams`, which includes this.
module ContactImportFile
  extend ActiveSupport::Concern

  PASTED_FILENAME = 'pasted-numbers.csv'.freeze
  # A .csv leaves the spreadsheet with whichever of these the operating system feels like; the extension is the
  # reliable signal and the content type is the fallback.
  CSV_CONTENT_TYPES = ['text/csv', 'application/csv', 'text/plain', 'application/vnd.ms-excel'].freeze
  MAX_PASTED_NUMBERS = 10_000
  MAX_IMPORT_BYTES = 10.megabytes
  # Long enough to look at a preview, change an option, look again and import; short enough that a signed id
  # copied out of a response is not a key to that file for ever.
  BLOB_TTL = 1.hour
  # Stamped on the blob when it is stored and checked when one is redeemed. `metadata` is a column ActiveStorage
  # already has, so none of this needs a migration.
  BLOB_ACCOUNT_KEY = 'contact_import_account_id'.freeze

  private

  # The uploaded file, stored exactly once.
  #
  # The preview and the import need the same bytes, and the dialog asks for them more than twice: see what the
  # file would do, change an option, see again, import. Re-uploading a 10MB CSV for each of those is the whole
  # transfer repeated for nothing. So the first request carrying a file stores it as a blob — the same
  # `ActiveStorage::Blob.create_and_upload!` the upload endpoint uses — and the preview hands back a signed id
  # that every request after it sends in place of the file. The import then attaches the blob it was given, so
  # the bytes the preview described are the bytes the import reads, not another copy of them.
  def import_blob
    return @import_blob if defined?(@import_blob)

    @import_blob = stored_blob || store_upload
  end

  # What a client sends back in place of the file. The paste path stores nothing, so it has none.
  def import_blob_signed_id
    import_blob&.signed_id(expires_in: BLOB_TTL)
  end

  # What to attach to the import: the blob the file was stored as, or the pasted numbers as the CSV they become.
  def import_attachment
    return import_blob if import_blob.present?
    return if pasted_csv.blank?

    { io: StringIO.new(pasted_csv), filename: PASTED_FILENAME, content_type: 'text/csv' }
  end

  # The same bytes, for the preview, which reads them and creates nothing. Read back out of the blob rather than
  # out of the upload: storing the file is what moves its read position, and the stored copy is what the import
  # will read, so previewing that copy is what keeps the two from ever disagreeing.
  def import_csv_content
    return pasted_csv if import_blob.blank?

    import_blob.download
  end

  # A signed id is a bearer token for one blob and the upload endpoint hands them out for every attachment in the
  # product, so what arrives here is not necessarily a CSV this account's import dialog stored. The account stamp
  # is what makes it one. An id that is expired, forged or for some other blob fails the same way.
  def stored_blob
    signed_id = params[:import_file_blob_id].presence
    return if signed_id.blank?

    blob = ActiveStorage::Blob.find_signed(signed_id.to_s)
    return blob if blob && blob.metadata[BLOB_ACCOUNT_KEY] == Current.account.id

    invalid_import!(:not_an_import_file, I18n.t('errors.contacts.import.not_an_import_file'))
  end

  def store_upload
    return if uploaded_csv.blank?

    ActiveStorage::Blob.create_and_upload!(
      io: uploaded_csv.tempfile,
      filename: uploaded_csv.original_filename,
      content_type: uploaded_csv.content_type,
      metadata: { BLOB_ACCOUNT_KEY => Current.account.id }
    )
  end

  def uploaded_csv
    return @uploaded_csv if defined?(@uploaded_csv)

    @uploaded_csv = params[:import_file].presence
    validate_csv_upload(@uploaded_csv) if @uploaded_csv
    @uploaded_csv
  end

  # `import_file` has to be a file. A client that sends the field as text used to reach `#read` on a String and
  # answer 500; the shape of a request parameter belongs here either way.
  #
  # The size cap was previously only applied when the preview read the file. It belongs on whatever is about to be
  # stored and then imported: `DataImportJob` reads the whole CSV into memory, so a file too large to preview is
  # also a file too large to import.
  def validate_csv_upload(upload)
    invalid_import!(:not_a_csv, I18n.t('errors.contacts.import.not_a_csv')) unless upload.respond_to?(:original_filename)

    invalid_import!(:too_large, I18n.t('errors.contacts.import.too_large', size: MAX_IMPORT_BYTES / 1.megabyte)) if upload.size > MAX_IMPORT_BYTES

    return if File.extname(upload.original_filename).downcase == '.csv'
    return if CSV_CONTENT_TYPES.include?(upload.content_type)

    invalid_import!(:not_a_csv, I18n.t('errors.contacts.import.not_a_csv'))
  end

  def pasted_csv
    return @pasted_csv if defined?(@pasted_csv)

    text = params[:phone_numbers]
    @pasted_csv = text.blank? ? nil : DataImport::PastedNumbers.csv(text)
    validate_pasted_count(@pasted_csv) if @pasted_csv
    @pasted_csv
  end

  def validate_pasted_count(csv)
    # The header is one of the lines.
    return if csv.count("\n") <= MAX_PASTED_NUMBERS + 1

    invalid_import!(:too_many_numbers, I18n.t('errors.contacts.import.too_many_numbers', count: MAX_PASTED_NUMBERS))
  end
end
