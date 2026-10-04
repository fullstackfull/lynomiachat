# What each row of a contacts CSV means, decided once and used twice: by the preview that runs before an import,
# and by the import itself. One classifier rather than two is the point — a preview that reasons about a file
# separately from the importer eventually promises something the importer then does differently.
#
# Nothing here writes. `classify` only reads the account, so a preview is a true dry run; the importer takes the
# results and performs the writes itself.
class DataImport::ContactRows
  LABELS_DELIMITER = ','.freeze
  # A row's own country wins; the batch's choice only fills a row that names none (docs/contacts/04-bulk-import.md).
  REGION_COLUMNS = %i[country_code country].freeze
  DUPLICATE_POLICIES = %w[update keep].freeze
  DEFAULT_DUPLICATE_POLICY = 'update'.freeze

  # classification is one of:
  #   :new_contact        a contact the account does not have yet
  #   :update_existing    a contact it already has, whose details this row rewrites
  #   :skip_existing      a contact it already has, left as it is (labels are still added)
  #   :duplicate_in_file  an earlier row in this same file already named this contact
  #   :no_identity        no email, phone or identifier, so nothing can ever reach this contact
  #   :invalid            refused, for the reason given
  Result = Struct.new(:number, :classification, :reason, :detail, :contact, :labels, :row, keyword_init: true) do
    def invalid? = classification == :invalid

    # Rows whose contact the importer writes. A duplicate carries the first row's contact, so both rows' labels
    # land on that one contact and nothing is inserted twice.
    def writes_contact? = %i[new_contact update_existing duplicate_in_file no_identity].include?(classification)
  end

  def initialize(account, options: {})
    @account = account
    @manager = DataImport::ContactManager.new(account)
    @batch_labels = normalize_labels(Array(options[:labels]).join(LABELS_DELIMITER))
    @default_region = options[:default_country].presence
    @duplicate_policy = DUPLICATE_POLICIES.include?(options[:duplicate_policy]) ? options[:duplicate_policy] : DEFAULT_DUPLICATE_POLICY
    @seen = {}
  end

  attr_reader :duplicate_policy

  # Look up every row's identities at once, for a caller that holds the whole batch. Without it a 500-row preview
  # costs three queries a row; with it, three in total.
  #
  # @param rows [Array] the rows about to be classified.
  def preload(rows)
    @manager.preload(rows.flat_map { |row| identity_keys_for(row.to_h.with_indifferent_access) })
  end

  # @param row [CSV::Row, Hash] one row.
  # @param number [Integer] its position in the file, 1-based, the header not counted.
  # @return [Result]
  def classify(row, number:)
    attributes = row.to_h.with_indifferent_access
    labels = row_labels(attributes)
    unknown = labels - catalogue_labels
    return build(number, :invalid, row: row, reason: 'unknown_labels', detail: unknown.join(', ')) if unknown.any?

    region = region_for(attributes)
    problem = phone_problem(attributes, region)
    return build(number, :invalid, row: row, reason: problem) if problem

    identified(number, row, attributes, labels, region)
  end

  private

  def identified(number, row, attributes, labels, region)
    keys = identity_keys(attributes, region)
    return unidentified(number, row, attributes, labels, region) if keys.empty?

    claimed = keys.filter_map { |key| @seen[key] }.first
    return duplicate(number, row, labels, claimed) if claimed

    existing = @manager.find_existing(attributes, region: region)
    contact = contact_for(existing, attributes, region)
    keys.each { |key| @seen[key] = { number: number, contact: contact } }
    result = build(number, classification_for(existing),
                   row: row, labels: labels, contact: contact, reason: existing && 'existing_contact')
    validated(result)
  end

  def unidentified(number, row, attributes, labels, region)
    validated(build(number, :no_identity, row: row, labels: labels, reason: 'missing_identity',
                                          contact: @manager.build_new(attributes, region: region)))
  end

  # A contact the account has is only rewritten when the chosen policy says so; under "keep" it is left exactly
  # as it is, and only its labels are added to.
  def contact_for(existing, attributes, region)
    return @manager.build_new(attributes, region: region) if existing.nil?
    return existing if @duplicate_policy == 'keep'

    @manager.assign_existing(existing, attributes, region: region)
  end

  # The last word belongs to the model. Whatever it refuses, for any reason this classifier does not know about,
  # becomes a refused row carrying the model's own messages — which is what the failed-records CSV has always
  # reported.
  def validated(result)
    return result if result.contact.valid?

    build(result.number, :invalid, row: result.row, reason: 'invalid_record',
                                   detail: result.contact.errors.full_messages.join(', '))
  end

  def duplicate(number, row, labels, claimed)
    build(number, :duplicate_in_file, row: row, labels: labels, contact: claimed[:contact],
                                      reason: 'duplicate_in_file', detail: claimed[:number].to_s)
  end

  def classification_for(existing)
    return :new_contact if existing.nil?

    @duplicate_policy == 'keep' ? :skip_existing : :update_existing
  end

  # Why the row's phone cannot be stored, or nil when it can. `Contact`'s rule is structural, so the only numbers
  # refused here are the ones it would refuse anyway — this names the real cause instead of "e164 format".
  def phone_problem(attributes, region)
    raw = attributes[:phone_number].to_s.strip
    return if raw.blank?
    return if normalized_phone(attributes, region).to_s.match?(Contacts::Phone::STRUCTURAL_FORMAT)

    raw.start_with?('0') && region.blank? ? 'phone_country_required' : 'phone_invalid'
  end

  def normalized_phone(attributes, region)
    DataImport::ContactManager.phone_number(attributes[:phone_number], region)
  end

  def identity_keys_for(attributes)
    identity_keys(attributes, region_for(attributes))
  end

  # Every identity a row carries, because two rows can collide on any one of them.
  def identity_keys(attributes, region)
    phone = normalized_phone(attributes, region)
    [
      attributes[:identifier].presence && [:identifier, attributes[:identifier].to_s],
      attributes[:email].presence && [:email, attributes[:email].to_s.downcase],
      phone.presence && [:phone_number, phone]
    ].compact
  end

  def region_for(attributes)
    REGION_COLUMNS.filter_map { |column| attributes[column].presence }.first || @default_region
  end

  def row_labels(attributes)
    (normalize_labels(attributes[:labels]) + @batch_labels).uniq
  end

  def normalize_labels(raw)
    raw.to_s.split(LABELS_DELIMITER).map { |label| label.strip.downcase }.compact_blank.uniq
  end

  def catalogue_labels
    @catalogue_labels ||= @account.labels.pluck(:title).map(&:downcase)
  end

  def build(number, classification, attributes = {})
    Result.new(number: number, classification: classification, labels: [], **attributes)
  end
end
