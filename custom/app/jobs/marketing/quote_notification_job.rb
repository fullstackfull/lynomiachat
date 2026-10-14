# Delivers the operator notification for one quote request, and records what happened.
#
# WHY A JOB RATHER THAN `mailer.deliver_later`. `deliver_later` hands the message to ActiveJob and nothing ever
# learns the outcome: the failure is logged inside the job and the row keeps no trace of it, so a relay that
# refuses every message looks exactly like one that works. The quote settings screen has to report a delivery
# problem reliably, so the delivery happens here, where its result can be written down.
#
# THE ROW IS NEVER INVALIDATED BY A DELIVERY PROBLEM. The request was saved and the visitor answered before
# this job ran; all that is recorded here is whether the alert got out. `update_columns` is deliberate -- it
# writes the outcome without validations or callbacks, so a row an operator has since edited, or one stored
# before a validation tightened, still gets its delivery recorded.
#
# NO RETRY. ActiveJob's default retry would re-send a message that may well have arrived, and a `discard_on`
# would hide a misconfigured relay. One attempt, recorded either way, and an operator who can see the failure
# on the settings screen and answer the lead by hand.
#
# ONE FAILURE CLASS IS INVISIBLE HERE, and it is worth naming rather than guarding: ApplicationMailer installs
# `rescue_from(*ExceptionList::SMTP_EXCEPTIONS)`, which is `Net::SMTPSyntaxError` alone, and ActionMailer runs
# `deliver_now` inside that handler. So an address the relay considers syntactically invalid is swallowed
# upstream and recorded here as delivered. Every other failure -- refused connection, authentication, timeout,
# DNS, a busy server -- has no handler and arrives in the rescue below.
class Marketing::QuoteNotificationJob < ApplicationJob
  queue_as :low

  # rubocop:disable Rails/SkipsModelValidations -- the outcome is the installation's own account of what
  # happened, so it is recorded on a row whose validations may since have tightened (see above).
  def perform(quote_id)
    quote = SiteQuoteRequest.find_by(id: quote_id)
    return if quote.nil?
    # Not an error state: an installation with no address configured is told so on every screen that matters,
    # and the row is the record. Nothing is attempted, so nothing is recorded.
    return unless Marketing::QuoteNotification.configured?

    Marketing::QuoteMailer.new_request(quote).deliver_now
    quote.update_columns(notification_attempted_at: Time.current, notification_error: nil)
  rescue StandardError => e
    Rails.logger.error("[Marketing] quote request ##{quote_id} notification failed: #{e.class}: #{e.message}")
    quote&.update_columns(notification_attempted_at: Time.current,
                          notification_error: "#{e.class}: #{e.message}".truncate(250))
  end
  # rubocop:enable Rails/SkipsModelValidations
end
