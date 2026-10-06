# Makes an outbound webhook failure findable, and stops the log line carrying the endpoint's URL.
#
# Webhooks::Trigger#handle_failure logged
#   "Exception: Invalid webhook URL #{@url} : #{error.message}"
# which has two problems. It names no account, inbox or event, so an operator reading it cannot tell whose
# integration broke or what it was carrying. And it prints the whole URL: a customer's webhook endpoint may carry a
# token in its query string, which puts a third party's credential in our logs.
#
# So the host is logged and the full URL is reduced to a digest -- enough to tell two endpoints apart and to match a
# line against a webhook row, and useless to anyone who reads the log.
#
# What this deliberately does NOT change: the exception is still swallowed rather than re-raised, so an account
# webhook failure still does not enter Sidekiq's retry or dead set. That is upstream's delivery policy, and turning
# it into a retry would start hammering a customer's broken endpoint -- a behaviour change, not an observability
# one. The gap is now visible instead of silent, which is what this phase is for.
module Custom::Webhooks::Trigger
  def handle_failure(error)
    report_failure(error)
    handle_error(error)
  end

  private

  def report_failure(error)
    Lynomia::OperatorLog.error(
      'OUTBOUND_WEBHOOK_FAILED',
      webhook_type: @webhook_type,
      event: @payload.is_a?(Hash) ? (@payload[:event] || @payload['event']) : nil,
      account: webhook_account_id,
      endpoint_host: endpoint_host,
      endpoint_digest: endpoint_digest,
      delivery: @delivery_id,
      http_status: http_status(error),
      error_class: error.class.name,
      error: error.message
    )
  end

  # The payload is the account's own webhook_data, so the account id is already in it; nothing is loaded to find it.
  def webhook_account_id
    return unless @payload.is_a?(Hash)

    @payload[:account]&.dig(:id) || @payload.dig('account', 'id')
  end

  def endpoint_host
    URI.parse(@url.to_s).host
  rescue URI::InvalidURIError
    'unparseable'
  end

  # Stable across deliveries to the same endpoint, and not reversible into the URL.
  def endpoint_digest
    Digest::SHA256.hexdigest(@url.to_s)[0, 12]
  end
end
