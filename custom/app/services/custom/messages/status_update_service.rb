# Makes a provider's refusal to deliver an outgoing message visible to an operator.
#
# Before this, a refusal was written to messages.status and content_attributes.external_error and nowhere else: no log
# line, no counter, no Sentry event, no admin view. The only way to learn that Meta had stopped delivering was to
# query the database, which means nobody learned it until a customer complained.
#
# This is the one place to emit from, because every channel's delivery status funnels through
# Messages::StatusUpdateService -- WhatsApp (Whatsapp::IncomingMessageBaseService#update_message_with_status),
# Facebook, SMS, Twilio, and the API inbox's own webhook failure path (Webhooks::Trigger#update_message_status).
#
# What it deliberately does NOT log: the message body, the recipient's phone number or email, and any token. It logs
# identifiers an operator can look the row up by, plus the provider's own error string, which is Meta's wording and
# carries no customer data.
#
# A refusal Meta will repeat for the same recipient is EXPECTED provider behaviour, so it is a warning and must not
# page anyone. A billing problem or an unrecognised code is actionable, so those are errors.
module Custom::Messages::StatusUpdateService
  private

  # The return value is #perform's return value, so it has to be super's and not the report's.
  def update_message_status
    was_failed = message.status == 'failed'
    result = super
    report_failure if !was_failed && message.status == 'failed'
    result
  end

  def report_failure
    failure = Whatsapp::DeliveryFailure.for(message)
    fields = {
      account: message.account_id,
      inbox: message.inbox_id,
      conversation: message.conversation&.display_id,
      message: message.id,
      channel: message.inbox&.channel_type,
      message_type: message.message_type,
      code: failure.code,
      classification: failure.classification,
      retry_policy: failure.retry_policy,
      provider_error: message.external_error
    }

    Lynomia::OperatorLog.emit(failure_level(failure), 'OUTGOING_DELIVERY_FAILED', **fields)
  end

  # Meta withholding a marketing template from one recipient is policy working as documented; it is logged so it can
  # be found, not so it wakes anyone. Everything else either has an operator-side fix (billing) or is a code this
  # installation has never classified, and both of those want eyes.
  def failure_level(failure)
    failure.recipient_scoped? ? :warn : :error
  end
end
