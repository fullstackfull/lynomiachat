# A pasted list of phone numbers as the file the importer already takes.
#
# "Paste numbers" is an entry path, not a second importer: the numbers become a one-column CSV, that CSV is
# attached to an ordinary `DataImport` the same way an uploaded file is, and `DataImportJob` reads it without
# knowing the difference (docs/contacts/04-bulk-import.md). So pasted numbers get the same normalization, the same
# duplicate handling, the same labels, the same per-row reasons and the same failed-records CSV.
module DataImport::PastedNumbers
  # One per line, or comma / semicolon / tab separated, which is what a copied spreadsheet column and a hand-typed
  # list each look like. Never split on a space: "+965 5111 2233" is one number.
  SEPARATORS = /[\r\n,;\t]+/
  HEADERS = %w[phone_number].freeze

  # @param text [String] what was pasted.
  # @return [String, nil] the CSV, or nil when the text holds no numbers at all.
  def self.csv(text)
    # Not deduplicated here: a repeated number is a row like any other, so the preview can say how many of the
    # pasted numbers were repeats and the importer collapses them onto one contact the same way it does for a CSV.
    numbers = text.to_s.split(SEPARATORS).map(&:strip).compact_blank
    return if numbers.empty?

    CSV.generate do |csv|
      csv << HEADERS
      numbers.each { |number| csv << [number] }
    end
  end
end
