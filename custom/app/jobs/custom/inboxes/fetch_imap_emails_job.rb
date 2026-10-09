# Lynomia Operations: make an email inbox's failure durable (docs/p9/04-operations-center.md §recording).
#
# This is the worst gap the P9 discovery found. A plain-password IMAP inbox whose password was rotated produces
# exactly one log line per poll (app/jobs/inboxes/fetch_imap_emails_job.rb:14-16) -- no Postgres row, no Redis
# counter, no Sentry event, and a SUCCESSFUL Sidekiq job. The OAuth variant needs ten consecutive failures
# (app/models/channel/email.rb:42) before even the Redis flag latches. And once it does latch,
# `should_fetch_email?` stops polling, so the inbox goes QUIET rather than erroring and nothing durable says why.
# That is the shape of the production incident on record for email inbox 74.
#
# The hook is `process_email_for_channel`, which is where the three outcomes are already distinguishable:
# it returns true on success, false on an OAuth error, and raises for everything else. The raised error is
# re-raised unchanged, so the OSS job's own rescues, logging and exception tracking behave exactly as before.
#
# Nothing here reads or writes a credential. `reason` is the exception's own message, bounded and collapsed by
# the recorder; `detail` carries the exception class name and nothing else.
module Custom::Inboxes::FetchImapEmailsJob
  # An invalid login shows up as a NoResponse or Bad response from the server. The connection-level errors in
  # ExceptionList::IMAP_EXCEPTIONS (ECONNREFUSED, timeouts, SocketError) are a different problem with a different
  # fix, so they are recorded as a different signal at a lower severity.
  AUTHENTICATION_ERRORS = [Net::IMAP::NoResponseError, Net::IMAP::BadResponseError].freeze

  private

  def process_email_for_channel(channel, interval)
    succeeded = super
    recorder = operations_recorder(channel)
    succeeded ? recorder.resolve_all : record_authentication_failure(recorder, 'The mail server refused the credentials')
    succeeded
  rescue StandardError => e
    record_fetch_error(channel, e)
    raise
  end

  def record_fetch_error(channel, error)
    recorder = operations_recorder(channel)
    if AUTHENTICATION_ERRORS.any? { |klass| error.is_a?(klass) }
      record_authentication_failure(recorder, error.message, error)
    else
      recorder.record(:connection_failed, severity: :warning, reason: error.message,
                                          detail: { code: error.class.name, channel_type: channel.class.name })
    end
  end

  def record_authentication_failure(recorder, reason, error = nil)
    recorder.record(
      :authentication_failed, severity: :critical, reason: reason,
                              detail: { code: error&.class&.name || 'OAuth2::Error', channel_type: 'Channel::Email' }
    )
  end

  def operations_recorder(channel)
    Operations::SignalRecorder.new(source: :email_channel, account: channel.account, subject: channel.inbox)
  end
end
