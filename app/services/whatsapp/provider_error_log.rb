# What a provider refusal is allowed to put in the log, and nothing else.
#
# `handle_error` used to write `response.body` -- the whole provider response, unparsed and unbounded. The
# product's own rule for operational records is the opposite of that, and it is already written down and
# enforced for the Operations table: `reason` is one sanitized line and `detail` carries allow-listed keys
# holding ids, codes and counts only (custom/app/services/operations/signal_recorder.rb:21-29 for the key
# allow-list, :145-155 for the one-line sanitizer). This applies the same rule to the one place that still
# logged a raw body.
#
# ALLOW-LIST, NOT DENY-LIST. Five values are taken by name. Everything else in the payload is dropped without
# being looked at, including `error_data` and `error_user_msg`/`error_user_title`: those are nested, free-form,
# customer-facing prose, and Meta puts the specific sentence about THIS call in them -- which for a send is
# routinely a sentence about the recipient. A key nobody listed is a key nobody checked, so an unknown key is
# never logged, even when a future payload adds one.
#
#   code             Meta's numeric error code -- the value its error reference is indexed by
#   error_subcode    the narrower code, where Meta sends one
#   type             the error class, e.g. OAuthException
#   fbtrace_id       the identifier Meta's own support asks for, and the only way to escalate a send
#   status           the HTTP status, read from the response rather than the body
#
# The sixth value is a CLASSIFICATION derived here from the status and from whether the body parsed at all. It
# is this code's own word, never the provider's, so it cannot carry anything.
#
# `message` IS SANITIZED, NOT TRUSTED. It is the one free-form value kept, because without it an operator
# reading the log has a code and no sentence. It is collapsed to one line, truncated, and passed through two
# removals: the credential shapes the Operations writer already removes, and contact identifiers -- an E.164-
# shaped number or an email address -- because Meta's send errors name the recipient in prose
# ("...not in allowed list", "...is not a valid WhatsApp user"). A recipient's number is exactly what this must
# not leak into a shared log.
#
# The product's parameter filtering (config/initializers/filter_parameter_logging.rb) does not help here: it
# filters request PARAMETERS, and this is a response body logged explicitly.
class Whatsapp::ProviderErrorLog
  FIELDS = %w[code error_subcode type fbtrace_id].freeze

  MAX_MESSAGE = 300

  REDACTED = '[redacted]'.freeze

  # A run of digits and the separators a provider might print inside a number. Whether a run is a contact
  # number is decided by COUNTING ITS DIGITS rather than by matching a length in the pattern, because the
  # separators make a character count mean nothing.
  CONTACT_RUN = /\+?\d[\d\s().-]*\d/

  # Nine, and the boundary is measured against the two things that collide. Meta's error codes are three to six
  # digits (100, 190, 131030) and its SUBCODES are seven (2655007) -- an earlier draft used seven and redacted
  # the subcode, which is one of the five values this log exists to keep. A full international number is longer
  # than either: country code plus national number reaches nine at the shortest. A run written with a leading
  # `+` is redacted whatever its length, because the `+` says what it is.
  MIN_CONTACT_DIGITS = 9

  EMAIL_PATTERN = /\b[\w.%+-]+@[\w-]+(\.[\w-]+)+\b/

  # The same two structural credential shapes the Operations writer removes: a URL's userinfo, and a key=value
  # pair whose KEY names a credential. Matched on structure rather than on entropy, for the reason recorded
  # there -- entropy matching redacts the message ids an operator needs and still misses a short password.
  #
  # One difference from that writer, and it is a correction rather than a variation: the key is matched with any
  # word prefix, so `access_token=` is caught. `\btoken` alone is not enough, because `_` is a word character
  # and there is therefore no word boundary inside `access_token` -- and `access_token` is the name Meta's own
  # errors use.
  SECRET_NAMES = 'password|passwd|pwd|token|api_key|apikey|secret|credential|authorization|bearer'.freeze
  CREDENTIAL_PATTERNS = [
    [%r{(//)[^/\s:@]+:[^/\s@]+(@)}, "\\1#{REDACTED}\\2"],
    [/\b([\w.-]*(?:#{SECRET_NAMES}))([\s:=]{1,3})[^\s&"'<>]+/i, "\\1\\2#{REDACTED}"]
  ].freeze

  def self.from_response(response)
    new(response).to_s
  end

  def initialize(response)
    @response = response
  end

  # One grep-able line. The prefix is fixed so an operator can find every provider refusal with one search.
  def to_s
    "WHATSAPP_PROVIDER_ERROR #{fields.map { |key, value| "#{key}=#{value}" }.join(' ')}"
  end

  private

  def fields
    allowed = FIELDS.index_with { |name| error[name] }
                    .compact
                    .transform_values { |value| scalar(value) }
                    .compact
    { 'status' => status, 'class' => classification }.merge(allowed).merge(message_field)
  end

  def message_field
    sanitized = sanitized_message
    sanitized.present? ? { 'message' => sanitized.inspect } : {}
  end

  # A value is logged only if it is already identifier-shaped. Meta sends `code` as an integer and `fbtrace_id`
  # as a short token; anything else under those names is a payload shape nobody here has seen, so it is dropped
  # rather than printed.
  def scalar(value)
    return value.to_s if value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
    return nil unless value.is_a?(String)

    value.match?(/\A[\w.:+-]{1,64}\z/) ? value : nil
  end

  def sanitized_message
    raw = error['message']
    return nil unless raw.is_a?(String)

    text = raw.gsub(/\s+/, ' ').strip
    CREDENTIAL_PATTERNS.each { |pattern, replacement| text = text.gsub(pattern, replacement) }
    text = text.gsub(EMAIL_PATTERN, REDACTED)
    text.gsub(CONTACT_RUN) { |run| contact?(run) ? REDACTED : run }.truncate(MAX_MESSAGE)
  end

  def contact?(run)
    run.start_with?('+') || run.count('0-9') >= MIN_CONTACT_DIGITS
  end

  # Read from the response, not from the body, so it is still right when the body is an HTML error page.
  def status
    @response.try(:code).to_s.presence || 'unknown'
  end

  # This code's own word for what happened, chosen from the status and from whether an error object was found.
  # `unparseable_body` is the interesting one: it says a refusal arrived in a shape this product does not know,
  # which is a prompt to look at the provider rather than at the account -- and it says so WITHOUT logging the
  # shape.
  def classification
    return 'unparseable_body' if error.blank?
    return 'provider_refused' if status.start_with?('4')
    return 'provider_error' if status.start_with?('5')

    'provider_rejected'
  end

  def error
    @error ||= begin
      parsed = @response.try(:parsed_response)
      parsed.is_a?(Hash) && parsed['error'].is_a?(Hash) ? parsed['error'] : {}
    rescue StandardError
      # A body that will not parse is the case this exists for. It must not raise into a send.
      {}
    end
  end
end
