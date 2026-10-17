# The one Odoo integration error (docs/odoo/03-adapter.md §6).
#
# WHAT A CALLER ACTUALLY NEEDS TO KNOW is not which exception Odoo raised but what to do next, and there are
# only five answers. `classification` is that answer, and it is decided here rather than at each call site, so
# a new caller cannot get the retry decision wrong.
#
# THE TWO DANGEROUS ONES. `not_sent` means the request provably never reached Odoo -- DNS, a refused
# connection, a connect timeout, an SSRF refusal -- so repeating it is safe. `unknown_outcome` means the
# request went out and no readable answer came back, so Odoo MAY HAVE ACTED. Repeating that is how a customer
# gets invoiced twice; the recovery is to search Odoo for our own stamp and adopt what is there.
# Commerce::HttpClient#send_once draws exactly this line for store APIs, and this is the same line.
#
# NO PROVIDER PROSE IN `message`. The message is the code and reason only. Odoo's own text, where it is worth
# keeping, travels separately in `detail` and is scrubbed by Odoo::SyncAttempt.scrub before anything stores it.
class Odoo::Error < StandardError
  CODES = %w[
    AUTH_INVALID PERMISSION_DENIED NOT_FOUND INVALID_REQUEST RATE_LIMITED
    SERVER_ERROR TIMEOUT INVALID_RESPONSE INVALID_URL UNREACHABLE
    ENDPOINT_MISSING RECORD_MISSING BUSINESS_RULE CONFLICT NOT_CONFIGURED
  ].freeze

  # Mirrors Odoo::SyncAttempt's outcomes, because an attempt records exactly this.
  PERMANENT = :permanent
  TRANSIENT = :transient
  NOT_SENT = :not_sent
  UNKNOWN_OUTCOME = :unknown_outcome
  NEEDS_REVIEW = :needs_review

  CLASSIFICATIONS = {
    # The operator must change something: a key, a right, a journal, our payload.
    'AUTH_INVALID' => PERMANENT,
    'PERMISSION_DENIED' => PERMANENT,
    'INVALID_REQUEST' => PERMANENT,
    'BUSINESS_RULE' => PERMANENT,
    'INVALID_URL' => PERMANENT,
    'NOT_CONFIGURED' => PERMANENT,
    # The transport is wrong for this server. Permanent for this attempt; re-detecting the version fixes it.
    'ENDPOINT_MISSING' => PERMANENT,
    'NOT_FOUND' => PERMANENT,
    # Odoo was there and busy, or broke. Worth repeating.
    'RATE_LIMITED' => TRANSIENT,
    'SERVER_ERROR' => TRANSIENT,
    # Before the request was written.
    'UNREACHABLE' => NOT_SENT,
    # After it was written, with nothing readable back.
    'TIMEOUT' => UNKNOWN_OUTCOME,
    'INVALID_RESPONSE' => UNKNOWN_OUTCOME,
    # Odoo and Lynomia disagree about reality: the record we wrote is gone, or two things claim to be one.
    'RECORD_MISSING' => NEEDS_REVIEW,
    'CONFLICT' => NEEDS_REVIEW
  }.freeze

  attr_reader :code, :reason, :detail, :http_status

  def initialize(code, reason: nil, detail: nil, http_status: nil)
    raise ArgumentError, "unknown odoo error code #{code}" unless CODES.include?(code)

    @code = code
    @reason = reason
    @detail = detail
    @http_status = http_status
    super([code, reason].compact.join(': '))
  end

  def classification
    CLASSIFICATIONS.fetch(code)
  end

  def retryable?
    [TRANSIENT, NOT_SENT].include?(classification)
  end

  # Safe for a JSON response or a flash message: a code, a reason from our own vocabulary, and nothing Odoo
  # wrote. The scrubbed detail is for the attempt log and the diagnostics page, never for an API consumer.
  def as_json(*)
    { code: code, reason: reason }.compact
  end
end
