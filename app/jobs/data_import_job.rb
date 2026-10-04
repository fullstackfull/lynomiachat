# TODO: logic is written tailored to contact import since its the only import available
# let's break this logic and clean this up in future
#
# What each row means is decided by `DataImport::ContactRows`, which the preview endpoint runs too, so the counts
# a user approves before an import are produced by the same code that then performs it
# (docs/contacts/04-bulk-import.md). The batch's own choices — labels for every row, a country for the rows that
# name none, what to do about a contact the account already has — travel on the import's `source_metadata`.

class DataImportJob < ApplicationJob
  queue_as :low
  retry_on ActiveStorage::FileNotFoundError, wait: 1.minute, attempts: 3

  def perform(data_import)
    @data_import = data_import
    @rows = DataImport::ContactRows.new(@data_import.account, options: batch_options)
    @contact_manager = DataImport::ContactManager.new(@data_import.account)
    begin
      process_import_file
      send_import_notification_to_admin
    rescue CSV::MalformedCSVError => e
      handle_csv_error(e)
    end
  end

  private

  def batch_options
    metadata = @data_import.source_metadata.to_h
    {
      labels: Array(metadata['labels']),
      default_country: metadata['default_country'],
      duplicate_policy: metadata['duplicate_policy']
    }
  end

  def process_import_file
    @data_import.update!(status: :processing)
    results = classify_rows
    accepted = results.reject(&:invalid?)

    import_contacts(accepted)
    update_data_import_status(results)
    save_failed_records_csv(results.select(&:invalid?).map { |result| rejected_row(result) })
  end

  def classify_rows
    results = []
    with_import_file do |file|
      csv_reader(file).each_with_index do |row, index|
        results << @rows.classify(row, number: index + 1)
      end
    end
    results
  end

  def rejected_row(result)
    row = result.row
    row['errors'] = error_message(result)
    row
  end

  def error_message(result)
    case result.reason
    when 'unknown_labels' then "Unknown labels: #{result.detail}"
    when 'phone_country_required' then I18n.t('errors.contacts.import.phone_country_required')
    when 'phone_invalid' then I18n.t('errors.contacts.phone_number.invalid')
    else result.detail.to_s
    end
  end

  def import_contacts(results)
    # Before the insert, not after: `synchronize:` re-reads every already-persisted instance from the database, so
    # an update that was still only in memory at that point would be thrown away.
    save_updated_contacts(results)
    # One object per contact, so two rows naming the same person insert once and contribute both their labels.
    contacts = results.filter_map(&:contact).uniq
    # <struct ActiveRecord::Import::Result failed_instances=[], num_inserts=1, ids=[444, 445], results=[]>
    Contact.import(contacts, synchronize: contacts, on_duplicate_key_ignore: true, track_validation_failures: true, validate: true, batch_size: 1000)
    DataImport::ContactLabels.new(@data_import.account)
                             .apply(results.map { |result| { contact: result.contact, labels: result.labels } })
  end

  # A contact the account already had is written once the whole file has been read, rather than row by row during
  # the pass, so a file that fails half way through has not already changed half the account.
  def save_updated_contacts(results)
    results.select { |result| result.classification == :update_existing }
           .map(&:contact).uniq
           .each(&:save)
  end

  # `processed_records` has always counted the rows this importer accepted rather than the rows it inserted — a
  # row naming a contact the account already has is accepted and then not inserted. `stats` carries the breakdown
  # the old counters could not express, and the import's own detail page already renders it.
  def update_data_import_status(results)
    counts = results.group_by(&:classification).transform_values(&:size)
    @data_import.update!(
      status: :completed,
      processed_records: results.count { |result| !result.invalid? },
      total_records: results.size,
      stats: @data_import.stats.to_h.merge('contacts' => contact_stats(counts))
    )
  end

  def contact_stats(counts)
    {
      'total' => counts.values.sum,
      'imported' => counts.fetch(:new_contact, 0),
      'updated' => counts.fetch(:update_existing, 0),
      'kept' => counts.fetch(:skip_existing, 0),
      'duplicate_in_file' => counts.fetch(:duplicate_in_file, 0),
      'without_identity' => counts.fetch(:no_identity, 0),
      'skipped' => counts.fetch(:invalid, 0)
    }
  end

  def save_failed_records_csv(rejected_contacts)
    csv_data = generate_csv_data(rejected_contacts)
    return if csv_data.blank?

    @data_import.failed_records.attach(io: StringIO.new(csv_data), filename: "#{Time.zone.today.strftime('%Y%m%d')}_contacts.csv",
                                       content_type: 'text/csv')
  end

  def generate_csv_data(rejected_contacts)
    headers = csv_headers
    headers << 'errors'
    return if rejected_contacts.blank?

    CSV.generate do |csv|
      csv << headers
      rejected_contacts.each do |record|
        csv << record
      end
    end
  end

  def handle_csv_error(error) # rubocop:disable Lint/UnusedMethodArgument
    @data_import.update!(status: :failed)
    send_import_failed_notification_to_admin
  end

  def send_import_notification_to_admin
    AdministratorNotifications::AccountNotificationMailer.with(account: @data_import.account).contact_import_complete(@data_import).deliver_later
  end

  def send_import_failed_notification_to_admin
    AdministratorNotifications::AccountNotificationMailer.with(account: @data_import.account).contact_import_failed.deliver_later
  end

  def csv_headers
    header_row = nil
    with_import_file do |file|
      header_row = csv_reader(file).first
    end
    header_row&.headers || []
  end

  def csv_reader(file)
    file.rewind
    raw_data = file.read
    utf8_data = raw_data.force_encoding('UTF-8')
    clean_data = utf8_data.valid_encoding? ? utf8_data : utf8_data.encode('UTF-16le', invalid: :replace, replace: '').encode('UTF-8')
    clean_data = clean_data.delete_prefix("\xEF\xBB\xBF")

    CSV.new(StringIO.new(clean_data), headers: true)
  end

  def with_import_file
    temp_dir = Rails.root.join('tmp/imports')
    FileUtils.mkdir_p(temp_dir)

    @data_import.import_file.open(tmpdir: temp_dir) do |file|
      file.binmode
      yield file
    end
  end
end
