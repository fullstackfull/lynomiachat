# Applies a shopper's own opt-out the moment they send it.
#
# ON THE INBOUND MESSAGE, not on an agent's later action: see Commerce::ConsentKeywords for
# why a refusal that depends on somebody reading it is not a refusal. One keyword message
# changes both classes at once, because that is what the person meant.
#
# EVERY CHANGE IS AUDITED through the trail Commerce already keeps, so "who decided this, and
# when" has one answer for an opt-out, an operator's record and a suppression alike. The
# evidence kept is the message id and the keyword matched -- never the message body, because a
# consent table is the last place a customer's words should be copied to.
class Commerce::ConsentListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.incoming? && !message.private?

    decision = Commerce::ConsentKeywords.decision(message.content)
    return if decision.nil? || message.conversation.contact.nil?

    Commerce::MessagingConsents.record(
      account: account, contact: message.conversation.contact,
      decision: Commerce::MessagingConsents::Decision.new(
        state: decision, source: 'shopper_keyword',
        evidence: { 'message_id' => message.id, 'keyword' => message.content.to_s.strip.downcase[0, 20] }
      )
    )
  end
end
