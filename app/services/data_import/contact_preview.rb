# What an import would do, before it is started. Nothing is created, nothing is changed.
#
# It runs the same `DataImport::ContactRows` the import runs, so the counts a user approves are produced by the
# code that then performs the work rather than by a second implementation that drifts from it.
#
# The classification of a row against the account needs a query, so the examined rows are bounded and the result
# says so: `total_rows` is the whole file, `previewed_rows` is what was examined. A file inside the bound is
# previewed exactly; past it the counts describe its first rows and the response states that, rather than
# reporting the rest as nothing (§C1.2 of the brief).
class DataImport::ContactPreview
  ROW_LIMIT = 500
  REPORTED_ROWS = 100
  REPORTED_COLUMNS = %w[name email phone_number identifier].freeze

  def initialize(account, raw_csv:, options: {})
    @account = account
    @raw_csv = raw_csv
    @options = options
    @rows = DataImport::ContactRows.new(account, options: options)
  end

  def perform
    results, total = classify
    {
      total_rows: total,
      previewed_rows: results.size,
      row_limit: ROW_LIMIT,
      duplicate_policy: @rows.duplicate_policy,
      default_country: @options[:default_country],
      labels: Array(@options[:labels]),
      counts: counts(results),
      rows: reported(results)
    }
  end

  private

  def classify
    results = []
    total = 0
    DataImport::ContactCsv.parse(@raw_csv).each do |row|
      total += 1
      next if results.size >= ROW_LIMIT

      results << @rows.classify(row, number: total)
    end
    [results, total]
  end

  # Every classification is reported, including the ones that are zero, so a caller never has to guess whether a
  # missing key means none or means not looked at.
  def counts(results)
    tallied = results.group_by(&:classification).transform_values(&:size)
    %i[new_contact update_existing skip_existing duplicate_in_file no_identity invalid]
      .index_with { |classification| tallied.fetch(classification, 0) }
  end

  # The row as it was written and the number it would be stored as, side by side, so a batch country's effect on a
  # local number is visible before the import runs rather than after it.
  def reported(results)
    results.first(REPORTED_ROWS).map do |result|
      result.row.to_h.with_indifferent_access.slice(*REPORTED_COLUMNS).symbolize_keys.merge(
        number: result.number,
        classification: result.classification,
        reason: result.reason,
        detail: result.detail,
        normalized_phone_number: result.contact&.phone_number
      )
    end
  end
end
