# Tells a prepared recovery message from a sent one (docs/commerce/31-sales-recovery.md §tracking). A recovery message
# counts as sent only when the conversation's outgoing, non-private message carries the recovery link it was prepared
# with, within SENT_WITHIN of preparing it: never because it was prepared, and never by Lynomia sending it. The cooldown
# and the panel's "sent" state come from these runs.
class Commerce::RecoveryListener < BaseListener
  SENT_WITHIN = 24.hours
  LINK = %r{https://[^\s<>"'\[\]()]+}

  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless message.outgoing? && !message.private? && message.content.to_s.include?('https://')

    digests = message.content.scan(LINK).map { |url| Commerce::RecoveryMessages.url_digest(url.sub(/[.,;:!?]+\z/, '')) }
    prepared(message).where(request_digest: digests).find_each { |run| sent!(run, message) }
  end

  private

  def prepared(message)
    Commerce::ActionRun.pending.where(conversation_id: message.conversation_id, action_type: Commerce::ActionRun::RECOVERY_MESSAGE,
                                      created_at: SENT_WITHIN.ago..)
  end

  def sent!(run, message)
    run.update!(status: :succeeded, completed_at: message.created_at, metadata: run.metadata.merge('message_id' => message.id))
    Commerce::AuditTrail.record('commerce.recovery.sent', auditable: run, user: message.sender.is_a?(User) ? message.sender : nil,
                                                          changes: { store_id: run.commerce_store_id, cart_id: run.external_resource_id,
                                                                     message_id: message.id })
    Commerce::Metrics.event('commerce.recovery.sent', provider: run.provider, store_id: run.commerce_store_id, run_id: run.id)
  end
end
