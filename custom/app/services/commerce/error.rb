# The one Lynomia Commerce error. The UI only ever sees `code` (and a safe `reason` for store URLs): provider
# responses, hosts' error pages and credentials never reach an error message.
class Commerce::Error < StandardError
  CODES = %w[
    STORE_UNAVAILABLE AUTH_INVALID PERMISSION_DENIED RATE_LIMITED TIMEOUT INVALID_RESPONSE
    NOT_FOUND INVALID_STORE_URL INVALID_QUERY ENCRYPTION_NOT_CONFIGURED STORE_ALREADY_CONNECTED PROVIDER_DISABLED
    PROTECTED_DATA_NOT_APPROVED INVALID_REQUEST ACTIONS_DISABLED ACTION_UNAVAILABLE ACTION_IN_PROGRESS ORDER_CHANGED
    INVALID_AMOUNT IDEMPOTENCY_CONFLICT WRITE_ACCESS_DENIED NOT_APPLIED PROVIDER_REJECTED REFUND_DECLINED
  ].freeze

  attr_reader :code, :reason

  def initialize(code, reason: nil)
    raise ArgumentError, "unknown commerce error code #{code}" unless CODES.include?(code)

    @code = code
    @reason = reason
    super([code, reason].compact.join(': '))
  end

  def as_json(*)
    { code: code, reason: reason }.compact
  end
end
