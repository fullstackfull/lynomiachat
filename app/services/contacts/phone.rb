# The server's one phone rule, for every path that turns what a person typed or a file carried into a stored
# `phone_number`.
#
# A number that names its own country ("+965...", or "00965..." as a keypad writes it) parses alone. A local one
# ("0551112233") parses only with a region the caller was explicitly told — a CSV column, a batch choice, the
# contact's own `additional_attributes.country_code`. There is no default region to fall back on: no account
# locale, no timezone, no inbox, no business number (docs/contacts/03-phase-b.md §B4). So a local number with no
# region returns nil rather than a guess, and the caller reports that the country is missing instead of storing
# a number that is wrong in a way nobody can see.
#
# This is the same rule `shared/helpers/phoneNumber.js` applies in the browser, kept in one place server-side so
# the two cannot drift: `Commerce::Phone.e164` delegates here.
#
# Not every phone code in the app: `Whatsapp::PhoneNormalizers::*` reconcile provider-specific quirks of an
# already-international WhatsApp id (Argentina's 9, Brazil's ninth digit, Mexico's 1) for contact lookup. That is
# a different question from "what did this person type", and they are deliberately untouched.
module Contacts::Phone
  # E.164 as `Contact` enforces it: structural, not a check that the number exists. It lives here because three
  # places ask the same question — the model's validation, its `phone_number_format` guard, and the CSV importer,
  # which reports *why* a number was refused.
  STRUCTURAL_FORMAT = /\A\+[1-9]\d{1,14}\z/

  # @param raw [String, nil] the number as it was given.
  # @param region [String, nil] an explicit ISO 3166-1 alpha-2 country code, or nil when none is known.
  # @return [String, nil] the E.164 number, or nil when it is not a valid number or its country is unknown.
  def self.e164(raw, region = nil)
    number = raw.to_s.strip.sub(/\A00/, '+')
    return if number.blank?

    parsed = if number.start_with?('+')
               TelephoneNumber.parse(number)
             else
               region.presence && TelephoneNumber.parse(number, region.to_s.downcase.to_sym)
             end
    parsed.e164_number if parsed&.valid?
  end
end
