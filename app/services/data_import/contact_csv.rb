# Reading a contacts CSV the way this importer has always read one: whatever encoding the spreadsheet saved, a
# byte-order mark stripped, invalid bytes replaced rather than raising. Extracted from `DataImportJob` so the
# preview endpoint reads an uploaded file identically — a preview that disagreed with the import about where the
# columns are would be worse than no preview.
module DataImport::ContactCsv
  BOM = "\xEF\xBB\xBF".freeze

  # @param raw [String] the file's bytes.
  # @return [CSV] a reader positioned at the first row, headers consumed.
  def self.parse(raw)
    utf8 = raw.to_s.dup.force_encoding('UTF-8')
    clean = utf8.valid_encoding? ? utf8 : utf8.encode('UTF-16le', invalid: :replace, replace: '').encode('UTF-8')
    CSV.new(StringIO.new(clean.delete_prefix(BOM)), headers: true)
  end
end
