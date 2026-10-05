# The one error the WhatsApp Template Manager shows. The UI only ever sees `code` plus, where Meta itself wrote
# something for a person to read, a safe `reason`. Access tokens, request headers and raw Graph bodies never reach an
# error message -- the full response goes to the log instead
# (docs/whatsapp-template-manager/01-meta-api-contract.md, PART 19).
class Whatsapp::Templates::Error < StandardError
  CODES = %w[
    ALREADY_AT_META SUBMIT_IN_FLIGHT NOT_SUBMITTABLE NOT_EDITABLE CATEGORY_NOT_EDITABLE NOT_DELETABLE
    CSAT_MANAGED_ELSEWHERE NO_WHATSAPP_INBOX INVALID_TEMPLATE NAME_TAKEN AUTH_INVALID RATE_LIMITED
    META_UNAVAILABLE META_REJECTED_REQUEST
  ].freeze

  attr_reader :code, :reason, :details

  # `details` carries field-level validation problems, as [{ field:, code:, limit: }], so the builder can point at the
  # input that is wrong instead of printing a sentence.
  def initialize(code, reason: nil, details: nil)
    raise ArgumentError, "unknown whatsapp template error code #{code}" unless CODES.include?(code)

    @code = code
    @reason = reason
    @details = details
    super([code, reason].compact.join(': '))
  end

  def as_json(*)
    { code: code, reason: reason, details: details }.compact
  end
end
