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
    record_operations_signal(error)
    handle_error(error)
  end

  private

  # The log line above is for an operator grepping journald after an incident; this row is for the Operations
  # Center, which needs the same fact sortable and joinable to an account. Neither the URL nor the payload goes
  # into it: `endpoint_host` is the host alone and the recorder drops anything that is not an allow-listed
  # scalar key (custom/app/services/operations/signal_recorder.rb).
  def record_operations_signal(error)
    account = Account.find_by(id: webhook_account_id)
    Operations::SignalRecorder.new(source: :webhook, account: account, subject: webhook_record(account)).record(
      :delivery_failed, severity: :warning, reason: error.message,
                        detail: { endpoint_host: endpoint_host, status_code: http_status(error), code: error.class.name }
    )
  end

  # The subject when it can be identified, so two broken endpoints in one account stay two rows.
  # `index_webhooks_on_account_id_and_url` is unique, so this is a single indexed lookup.
  def webhook_record(account)
    return nil if account.nil?

    ::Webhook.find_by(account_id: account.id, url: @url)
  end

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
