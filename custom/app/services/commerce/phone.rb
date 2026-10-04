# Phone numbers for customer matching, via the telephone_number gem the rest of the app uses.
module Commerce::Phone
  # E.164 for a stored store phone, or nil. International numbers ("+..." or "00...") parse on their own; a local
  # number ("055...") only with the order's billing country. No country and no "+" means no match, never a guess.
  # The rule itself lives in `Contacts::Phone`, which the contact form and the CSV importer apply too, so a number
  # a store reports and the same number typed into a contact normalize identically.
  def self.e164(raw, country = nil) = Contacts::Phone.e164(raw, country)

  # The national significant number ("551112233" for +966551112233): a substring of the formats stores keep
  # ("+966551112233", "0551112233", "00966551112233"), used only to discover candidates.
  def self.search_term(e164)
    parsed = TelephoneNumber.parse(e164.to_s)
    return unless parsed.valid?

    parsed.e164_number.delete_prefix("+#{parsed.country.country_code}")
  end
end
