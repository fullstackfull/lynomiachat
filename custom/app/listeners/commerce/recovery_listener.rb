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
    claim_targeting(run, message.created_at)
    Commerce::AuditTrail.record('commerce.recovery.sent', auditable: run, user: message.sender.is_a?(User) ? message.sender : nil,
                                                          changes: { store_id: run.commerce_store_id, cart_id: run.external_resource_id,
                                                                     message_id: message.id })
    Commerce::Metrics.event('commerce.recovery.sent', provider: run.provider, store_id: run.commerce_store_id, run_id: run.id)
  end

  # `targeted_at` on the durable cart row means exactly one thing: a real Lynomia abandoned-cart outreach was
  # successfully accepted for sending. This is that moment and the only one — a confirmed outgoing, non-private
  # message carrying the link the recovery message was prepared with. It is deliberately NOT set when a rule merely
  # matches, when a job is enqueued, when a template is chosen, or when a send fails or is refused.
  #
  # One atomic statement guarded on `targeted_at IS NULL`: two workers confirming near-simultaneous sends set it
  # once, and the first send wins. That is the concurrency protection — not a read-then-write, which two workers
  # can interleave, and not a new lock system. `update_all` is what makes it a single conditional UPDATE; the
  # column is a timestamp with no validations to skip.
  def claim_targeting(run, sent_at)
    Commerce::Cart.where(commerce_store_id: run.commerce_store_id, provider_cart_id: run.external_resource_id, targeted_at: nil)
                  .update_all(targeted_at: sent_at, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
