# Phone numbers for customer matching, via the telephone_number gem the rest of the app uses.
module Commerce::Phone
  # E.164 for a stored store phone, or nil. International numbers ("+..." or "00...") parse on their own; a local
  # number ("055...") only with the order's billing country. No country and no "+" means no match, never a guess.
  def self.e164(raw, country = nil)
    number = raw.to_s.strip.sub(/\A00/, '+')
    return if number.blank?

    parsed = number.start_with?('+') ? TelephoneNumber.parse(number) : country.presence && TelephoneNumber.parse(number, country.to_s.downcase.to_sym)
    parsed.e164_number if parsed&.valid?
  end

  # The national significant number ("551112233" for +966551112233): a substring of the formats stores keep
  # ("+966551112233", "0551112233", "00966551112233"), used only to discover candidates.
  def self.search_term(e164)
    parsed = TelephoneNumber.parse(e164.to_s)
    return unless parsed.valid?

    parsed.e164_number.delete_prefix("+#{parsed.country.country_code}")
  end
end
